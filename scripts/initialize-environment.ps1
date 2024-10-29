param(
    [ValidateSet("mhsm", "akvpremium")]
    [string]$kvType = "akvpremium",

    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",
    [string]$resourceGroupLocation = "$env:RESOURCE_GROUP_LOCATION",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",
    [string]$secretDir = "$samplesRoot/demo-resources.secret",

    [string]$maaEndpoint = "https://sharedneu.neu.attest.azure.net",

    [string]$overridesFilePath = "",
    [string]$resourceGroupTags = "",

    [string]$environmentConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$secretstoreConfig = "$privateDir/secretstores.config",
    [string]$localSecretStore = "$secretDir/$persona-local-store"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/common/common.psm1
Import-Module $PSScriptRoot/azure-helpers/azure-helpers.psm1 -Force -DisableNameChecking

Write-Log OperationStarted `
    "Creating resource group '$resourceGroup' in '$resourceGroupLocation'..."
az group create --location $resourceGroupLocation --name $resourceGroup --tags $resourceGroupTags

$result = @{
    kek          = @{}
    dek          = @{}
    sa           = @{}
    oidcsa       = @{}
    maa_endpoint = ""
}

$uniqueString = Get-UniqueString($resourceGroup)
if ($overridesFilePath -ne "") {
    $overrides = Get-Content $overridesFilePath | Out-String | ConvertFrom-StringData
}
else {
    $overrides = @{}
}

# TODO(phanic): Scrub the resource creation required for non-collaborator personas.
$objectId = GetLoggedInEntityObjectId
$kvName = $($overrides['$KEYVAULT_NAME'] ?? "${uniqueString}kv")
$mhsmName = $($overrides['$MHSM_NAME'] ?? "${uniqueString}mhsm")
if ($kvType -eq "mhsm") {
    Write-Log OperationStarted `
        "Creating HSM '$mhsmName' in resource group '$resourceGroup'..."
    $keyStore = Create-Hsm `
        -resourceGroup $resourceGroup `
        -hsmName $mhsmName `
        -adminObjectId $objectId `
        -privateDir $privateDir

    $result.kek.kv = $keyStore
    # Creating the Key Vault upfront so as not to run into naming issues
    # while storing the wrapped DEK
    Write-Log OperationStarted `
        "Creating Key Vault '$kvName' to store the wrapped DEK..."
    $result.dek.kv = Create-KeyVault `
        -resourceGroup $resourceGroup `
        -keyVaultName $kvName `
        -adminObjectId $objectId
}
else {
    Write-Log OperationStarted `
        "Creating Key Vault '$kvName' in resource group '$resourceGroup'..."
    $result.kek.kv = Create-KeyVault `
        -resourceGroup $resourceGroup `
        -keyVaultName $kvName `
        -sku premium `
        -adminObjectId $objectId
    $result.dek.kv = $result.kek.kv
}

$saName = $($overrides['$STORAGE_ACCOUNT_NAME'] ?? "${uniqueString}sa")
$result.sa = Create-Storage-Resources `
    -resourceGroup $resourceGroup `
    -storageAccountName @($saName) `
    -objectId $objectId

$oidcsaName = $($overrides['$OIDC_STORAGE_ACCOUNT_NAME'] ?? "${uniqueString}oidcsa")
$result.oidcsa = Create-Storage-Resources `
    -resourceGroup $resourceGroup `
    -storageAccountName @($oidcsaName) `
    -objectId $objectId

$result.maa_endpoint = $maaEndpoint

Write-Log OperationStarted `
    "Generating secret store configuration for '$persona'..."

Write-Log Verbose `
    "Adding local secret store '$localSecretStore'..."
az cleanroom secretstore add `
    --name $persona-local-store `
    --config $secretstoreConfig `
    --backingstore-type Local_File `
    --backingstore-path $localSecretStore

Write-Log Verbose `
    "Adding DEK store '$($result.dek.kv.id)'..."
az cleanroom secretstore add `
    --name $persona-dek-store `
    --config $secretstoreConfig `
    --backingstore-type Azure_KeyVault `
    --backingstore-id $result.dek.kv.id 

Write-Log Verbose `
    "Adding KEK store '$($result.kek.kv.id)'..."
az cleanroom secretstore add `
    --name $persona-kek-store `
    --config $secretstoreConfig `
    --backingstore-type Azure_KeyVault_Managed_HSM `
    --backingstore-id $result.kek.kv.id `
    --attestation-endpoint $result.maa_endpoint

Write-Log OperationCompleted `
    "Secret store configuration written to '$secretstoreConfig'."

$result | ConvertTo-Json -Depth 100 | Out-File "$environmentConfig"
Write-Log OperationCompleted `
    "Initialization configuration written to '$environmentConfig'."

return $result