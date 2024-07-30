param(
    [Parameter(Mandatory = $true)]
    [string]$resourceGroup,
    [Parameter(Mandatory = $true)]
    [string]$governanceClient,
    [Parameter(Mandatory = $true)]
    [string]$contractId,
    [string]$outDir = ""

)

$ErrorActionPreference = 'Stop'

if ($outDir -eq "") {
    $outDir = "$PSScriptRoot/demo-resources/$resourceGroup"
}
else {
    $outDir = "$outDir/$resourceGroup"
}
. $outDir/names.generated.ps1

Import-Module $PSScriptRoot/../common/infra-scripts/azure-helpers.psm1 -Force -DisableNameChecking

$isMhsm = $(-not $($MHSM_NAME -eq ""))

if ($isMhsm) {
    $keyVaultName = $MHSM_NAME
}
else {
    $keyVaultName = $KEYVAULT_NAME
}

$managedIdentity = (az identity show --name $MANAGED_IDENTITY_NAME --resource-group $resourceGroup | ConvertFrom-Json)
CheckLastExitCode

Write-Host "Assigning permissions to the managed identity on the storage account"
$storageAccount = (az storage account show `
        --name $STORAGE_ACCOUNT_NAME `
        --resource-group $resourceGroup) | ConvertFrom-Json

# Cleanroom needs both read/write permissions on storage account, hence assigning Storage Blob Data Contributor.
az role assignment create `
    --role "Storage Blob Data Contributor" `
    --scope $storageAccount.id `
    --assignee-object-id $managedIdentity.principalId `
    --assignee-principal-type ServicePrincipal
CheckLastExitCode

if ($isMhsm) {
    Write-Host "Assigning permissions to the managed identity on the HSM"
    $roleAssignment = (az keyvault role assignment list `
            --assignee-object-id $managedIdentity.principalId `
            --hsm-name $MHSM_NAME `
            --role "Managed HSM Crypto User") | ConvertFrom-Json

    if ($roleAssignment.Length -eq 1) {
        Write-Host "Crypto User permission for managed identity on the HSM already exists, skipping assignment"
    }
    else {
        Write-Host "Assigning Crypto User permission to the managed identity on the HSM"
        az keyvault role assignment create `
            --role "Managed HSM Crypto User" `
            --scope "/" `
            --assignee-object-id $managedIdentity.principalId `
            --hsm-name $MHSM_NAME `
            --assignee-principal-type ServicePrincipal
    }
}
else {
    $keyVaultResult = (az keyvault show --name $KEYVAULT_NAME --resource-group $resourceGroup) | ConvertFrom-Json
    $roleAssignment = (az role assignment list `
            --assignee $managedIdentity.principalId `
            --scope $keyVaultResult.id `
            --role "Key Vault Crypto Officer") | ConvertFrom-Json

    if ($roleAssignment.Length -eq 1) {
        Write-Host "Key Vault Crypto Officer permission for managed identity on the key vault already exists, skipping assignment"
    }
    else {
        Write-Host "Assigning Key Vault Crypto Officer to the managed identity on the Key Vault"
        az role assignment create `
            --role "Key Vault Crypto Officer" `
            --scope $keyVaultResult.id `
            --assignee-object-id $managedIdentity.principalId `
            --assignee-principal-type ServicePrincipal
        CheckLastExitCode
    }
}

Write-Host "Assigning Secrets User permission to the managed identity on the Key Vault"
$keyVaultResult = (az keyvault show `
        --name $KEYVAULT_NAME `
        --resource-group $resourceGroup) | ConvertFrom-Json
az role assignment create `
    --role "Key Vault Secrets User" `
    --scope $keyVaultResult.id `
    --assignee-object-id $managedIdentity.principalId `
    --assignee-principal-type ServicePrincipal
CheckLastExitCode

# Set OIDC issuer.
$currentUser = (az account show) | ConvertFrom-Json
$tenantId = $currentUser.tenantid
$tenantData = (az cleanroom governance oidc-issuer show `
        --governance-client $governanceClient `
        --query "tenantData" | ConvertFrom-Json)
if ($null -ne $tenantData -and $tenantData.tenantId -eq $tenantId) {
    Write-Host -ForegroundColor Yellow "OIDC issuer already set for the tenant, skipping."
    $issuerUrl = $tenantData.issuerUrl
}
else {
    Write-Host "Setting up OIDC issuer for the tenant $tenantId"
    $storageAccountResult = (az storage account create `
            --resource-group "$resourceGroup" `
            --allow-shared-key-access false `
            --name "${OIDC_STORAGE_ACCOUNT_NAME}" `
            --allow-blob-public-access true) | ConvertFrom-Json

    $objectId = GetLoggedInEntityObjectId
    Write-Host "Assigning 'Storage Blob Data Contributor' permissions to logged in user"
    az role assignment create `
        --role "Storage Blob Data Contributor" `
        --scope $storageAccountResult.id `
        --assignee-object-id $objectId `
        --assignee-principal-type $(Get-Assignee-Principal-Type)
    CheckLastExitCode

    if ($env:GITHUB_ACTIONS -eq "true") {
        $sleepTime = 60
        Write-Host "Waiting for $sleepTime seconds for permissions to get applied"
        Start-Sleep -Seconds $sleepTime
    }

    az storage container create `
        --name "${OIDC_CONTAINER_NAME}" `
        --account-name "${OIDC_STORAGE_ACCOUNT_NAME}" `
        --public-access blob `
        --auth-mode login
    CheckLastExitCode

    @"
{
"issuer": "https://${OIDC_STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${OIDC_CONTAINER_NAME}",
"jwks_uri": "https://${OIDC_STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${OIDC_CONTAINER_NAME}/openid/v1/jwks",
"response_types_supported": [
"id_token"
],
"subject_types_supported": [
"public"
],
"id_token_signing_alg_values_supported": [
"RS256"
]
}
"@ > $outDir/openid-configuration.json

    az storage blob upload `
        --container-name "${OIDC_CONTAINER_NAME}" `
        --file $outDir/openid-configuration.json `
        --name .well-known/openid-configuration `
        --account-name "${OIDC_STORAGE_ACCOUNT_NAME}" `
        --overwrite `
        --auth-mode login
    CheckLastExitCode

    $ccfEndpoint = (az cleanroom governance client show --name $governanceClient | ConvertFrom-Json)
    $url = "$($ccfEndpoint.ccfEndpoint)/app/oidc/keys"
    curl -s -k $url | jq > $outDir/jwks.json

    az storage blob upload `
        --container-name "${OIDC_CONTAINER_NAME}" `
        --file $outDir/jwks.json `
        --name openid/v1/jwks `
        --account-name "${OIDC_STORAGE_ACCOUNT_NAME}" `
        --overwrite `
        --auth-mode login
    CheckLastExitCode

    az cleanroom governance oidc-issuer set-issuer-url `
        --governance-client $governanceClient `
        --url "https://${OIDC_STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${OIDC_CONTAINER_NAME}"
    $tenantData = (az cleanroom governance oidc-issuer show `
            --governance-client $governanceClient `
            --query "tenantData" | ConvertFrom-Json)
    $issuerUrl = $tenantData.issuerUrl
}

Write-Host "Setting up federation on managed identity with issuerUrl $issuerUrl and subject $contractId"
az identity federated-credential create `
    --name "$contractId-federation" `
    --identity-name $MANAGED_IDENTITY_NAME `
    --resource-group $resourceGroup `
    --issuer $issuerUrl `
    --subject $contractId
if ($env:GITHUB_ACTIONS -eq "true") {
    $sleepTime = 30
    # See Note at https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster#create-the-federated-identity-credential
    Write-Host "Waiting for $sleepTime seconds for federated identity credential to propagate after it is added"
    Start-Sleep -Seconds $sleepTime
}

function Get-Assignee-Principal-Type {
    if ($env:GITHUB_ACTIONS -eq "true") {
        return "ServicePrincipal"
    }
    else {
        return "User"
    }
}