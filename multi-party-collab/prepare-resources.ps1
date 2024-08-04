param(
    [Parameter(Mandatory = $true)]
    [string]$resourceGroup,

    [Parameter(Mandatory = $true)]
    [ValidateSet("mhsm", "akvpremium")]
    [string]$kvType,

    [string]$outDir = "",

    [Parameter()]
    [string]$backupKv = "",

    [string]$overridesFilePath = "",

    [string]$resourceGroupTags = ""
)

$ErrorActionPreference = 'Stop'

Import-Module $PSScriptRoot/azure-helpers.psm1 -Force -DisableNameChecking

if ($outDir -eq "") {
    $outDir = "./demo-resources.private"
}

pwsh $PSScriptRoot/generate-names.ps1 `
    -resourceGroup $resourceGroup `
    -kvType $kvType `
    -overridesFilePath $overridesFilePath `
    -backupKv $backupKv `
    -outDir $outDir

. $outDir/names.generated.ps1
$sandbox_common = $outDir

# create resource group
# Write-Host "Creating resource group $resourceGroup in $RESOURCE_GROUP_LOCATION"
# az group create --location $RESOURCE_GROUP_LOCATION --name $resourceGroup --tags $resourceGroupTags

$objectId = GetLoggedInEntityObjectId
$result = @{
    kek          = @{}
    dek          = @{}
    sa           = @{}
    mi           = @{}
    maa_endpoint = ""
}

if ($kvType -eq "mhsm") {
    Write-Host "Creating HSM $MHSM_NAME in resource group $resourceGroup"
    $keyStore = Create-Hsm `
        -resourceGroup $resourceGroup `
        -hsmName $MHSM_NAME `
        -adminObjectId $objectId `
        -outDir $sandbox_common

    $result.kek.kv = $keyStore
    # Creating the Key Vault upfront so as not to run into naming issues
    # while storing the wrapped DEK
    Write-Host "Creating Key Vault to store the wrapped DEK"
    $result.dek.kv = Create-KeyVault `
        -resourceGroup $resourceGroup `
        -keyVaultName $KEYVAULT_NAME `
        -adminObjectId $objectId
}
else {
    Write-Host "Creating Key Vault $KEYVAULT_NAME in resource group $resourceGroup"
    $result.kek.kv = Create-KeyVault `
        -resourceGroup $resourceGroup `
        -keyVaultName $KEYVAULT_NAME `
        -sku premium `
        -adminObjectId $objectId
    $result.dek.kv = $result.kek.kv
}

$storageAccount = Create-Storage-Resources `
    -resourceGroup $resourceGroup `
    -storageAccountName @($STORAGE_ACCOUNT_NAME) `
    -objectId $objectId
$result.sa = $storageAccount

Write-Host "Creating managed identity $MANAGED_IDENTITY_NAME in resource group $resourceGroup"
$managedIdentityResult = (az identity create `
        --name $MANAGED_IDENTITY_NAME `
        --resource-group $resourceGroup) | ConvertFrom-Json
$result.mi = $managedIdentityResult

$result.maa_endpoint = $MAA_URL

$result | ConvertTo-Json -Depth 100 > $outDir/resources.generated.json
return $result