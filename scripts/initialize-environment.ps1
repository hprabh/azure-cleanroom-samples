param(
    [ValidateSet("mhsm", "akvpremium")]
    [string]$kvType = "akvpremium",

    [string]$resourceGroup = "$env:RESOURCE_GROUP",
    [string]$resourceGroupLocation = "$env:RESOURCE_GROUP_LOCATION",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",

    [string]$maaEndpoint = "https://sharedneu.neu.attest.azure.net",

    [string]$overridesFilePath = "",
    [string]$resourceGroupTags = "",

    [string]$environmentConfig = "$privateDir/$resourceGroup.generated.json"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/azure-helpers/azure-helpers.psm1 -Force -DisableNameChecking

Write-Host -ForegroundColor DarkGray `
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
    Write-Host -ForegroundColor DarkGray `
        "Creating HSM '$mhsmName' in resource group '$resourceGroup'..."
    $keyStore = Create-Hsm `
        -resourceGroup $resourceGroup `
        -hsmName $mhsmName `
        -adminObjectId $objectId `
        -privateDir $privateDir

    $result.kek.kv = $keyStore
    # Creating the Key Vault upfront so as not to run into naming issues
    # while storing the wrapped DEK
    Write-Host -ForegroundColor DarkGray `
        "Creating Key Vault '$kvName' to store the wrapped DEK..."
    $result.dek.kv = Create-KeyVault `
        -resourceGroup $resourceGroup `
        -keyVaultName $kvName `
        -adminObjectId $objectId
}
else {
    Write-Host -ForegroundColor DarkGray `
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

$result | ConvertTo-Json -Depth 100 | Out-File "$environmentConfig"
Write-Host -ForegroundColor Yellow `
    "Initialization configuration written to '$environmentConfig'."
return $result