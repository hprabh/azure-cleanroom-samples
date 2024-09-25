param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$scenario,

    [string]$cgsClient = "$env:MEMBER_NAME-client",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$publicDir = "./demo-resources.public",
    [string]$privateDir = "./demo-resources.private",
    [string]$secretDir = "./demo-resources.secret",
    [string]$oidcContainerName = "cgs-oidc",

    [string]$keyStore = "$secretDir/keys",
    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$resourceConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$collabConfig = "$privateDir/$resourceGroup-$scenario.generated.json",
    [string]$contractId = "collab-$scenario" # A unique identifier to refer to this collaboration.
)

$ErrorActionPreference = 'Stop'

Import-Module $PSScriptRoot/../azure-helpers/azure-helpers.psm1 -Force -DisableNameChecking
$collabConfigResult = (Get-Content $collabConfig | ConvertFrom-Json)
$resourceConfigResult = Get-Content $resourceConfig | ConvertFrom-Json

#
# Create a KEK with SKR policy, wrap DEKs with the KEK and put in kv.
#
az cleanroom config wrap-deks `
    --contract-id $contractId `
    --cleanroom-config $collabConfigResult.configFile `
    --datastore-config $datastoreConfig `
    --key-store $keyStore `
    --governance-client $cgsClient

#
# Setup managed identity access to storage/KV in collaborator tenant.
#
$managedIdentity = $collabConfigResult.mi
$kekVault = $resourceConfigResult.kek.kv
$dekVault = $resourceConfigResult.dek.kv

Write-Host "Assigning permissions to the managed identity on the storage account"
# Cleanroom needs both read/write permissions on storage account, hence assigning Storage Blob Data Contributor.
az role assignment create `
    --role "Storage Blob Data Contributor" `
    --scope $resourceConfigResult.sa.id `
    --assignee-object-id $managedIdentity.principalId `
    --assignee-principal-type ServicePrincipal
CheckLastExitCode

if ($kekVault.type -eq "Microsoft.KeyVault/managedHSMs") {
    Write-Host "Assigning permissions to the managed identity on the HSM"
    $roleAssignment = (az keyvault role assignment list `
            --assignee-object-id $managedIdentity.principalId `
            --hsm-name $kekVault.name `
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
            --hsm-name $kekVault.name `
            --assignee-principal-type ServicePrincipal
        CheckLastExitCode
    }
}
elseif ($kekVault.type -eq "Microsoft.KeyVault/vaults") {
    Write-Host "Assigning permissions to the managed identity on the Key Vault"
    $roleAssignment = (az role assignment list `
            --assignee $managedIdentity.principalId `
            --scope $kekVault.id `
            --role "Key Vault Crypto Officer") | ConvertFrom-Json

    if ($roleAssignment.Length -eq 1) {
        Write-Host "Key Vault Crypto Officer permission for managed identity on the key vault already exists, skipping assignment"
    }
    else {
        Write-Host "Assigning Key Vault Crypto Officer to the managed identity on the Key Vault"
        az role assignment create `
            --role "Key Vault Crypto Officer" `
            --scope $kekVault.id `
            --assignee-object-id $managedIdentity.principalId `
            --assignee-principal-type ServicePrincipal
        CheckLastExitCode
    }
}

Write-Host "Assigning Secrets User permission to the managed identity on the Key Vault"
az role assignment create `
    --role "Key Vault Secrets User" `
    --scope $dekVault.id `
    --assignee-object-id $managedIdentity.principalId `
    --assignee-principal-type ServicePrincipal
CheckLastExitCode

#
# Setup OIDC issuer and federated credential on managed identity.
#
$tenantId = az account show --query "tenantId" --output tsv
$tenantData = (az cleanroom governance oidc-issuer show `
        --governance-client $cgsClient `
        --query "tenantData" | ConvertFrom-Json)
if ($null -ne $tenantData -and $tenantData.tenantId -eq $tenantId) {
    Write-Host -ForegroundColor Yellow "OIDC issuer already set for the tenant, skipping."
    $issuerUrl = $tenantData.issuerUrl
}
else {
    Write-Host "Setting up OIDC issuer for the tenant $tenantId"

    Write-Host "Enabling public blob access for $($resourceConfigResult.oidcsa.name)"
    az storage account update --allow-blob-public-access true `
        --name $resourceConfigResult.oidcsa.name

    $sleepTime = 30
    Write-Host "Waiting for $sleepTime seconds for public blob access to be enabled..."
    Start-Sleep -Seconds $sleepTime

    Write-Host "Creating public access blob container '$oidcContainerName' in $($resourceConfigResult.oidcsa.name)"
    az storage container create `
        --name $oidcContainerName `
        --account-name $resourceConfigResult.oidcsa.name `
        --public-access blob `
        --auth-mode login
    CheckLastExitCode

    @"
{
"issuer": "https://$($resourceConfigResult.oidcsa.name).blob.core.windows.net/$oidcContainerName",
"jwks_uri": "https://$($resourceConfigResult.oidcsa.name).blob.core.windows.net/$oidcContainerName/openid/v1/jwks",
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
"@ > $privateDir/openid-configuration.json

    az storage blob upload `
        --container-name $oidcContainerName `
        --file $privateDir/openid-configuration.json `
        --name .well-known/openid-configuration `
        --account-name $resourceConfigResult.oidcsa.name `
        --overwrite `
        --auth-mode login
    CheckLastExitCode

    $ccfEndpoint = (Get-Content "$publicDir/ccfEndpoint")
    $url = "$($ccfEndpoint.ccfEndpoint)/app/oidc/keys"
    curl -s -k $url | jq > $privateDir/jwks.json

    az storage blob upload `
        --container-name $oidcContainerName `
        --file $privateDir/jwks.json `
        --name openid/v1/jwks `
        --account-name $resourceConfigResult.oidcsa.name `
        --overwrite `
        --auth-mode login
    CheckLastExitCode

    az cleanroom governance oidc-issuer set-issuer-url `
        --governance-client $cgsClient `
        --url "https://$($resourceConfigResult.oidcsa.name).blob.core.windows.net/$oidcContainerName"
    $tenantData = (az cleanroom governance oidc-issuer show `
            --governance-client $cgsClient `
            --query "tenantData" | ConvertFrom-Json)
    $issuerUrl = $tenantData.issuerUrl
}

Write-Host "Setting up federation on managed identity with issuerUrl $issuerUrl and subject $contractId"
az identity federated-credential create `
    --name "$contractId-federation" `
    --identity-name $collabConfigResult.mi.name `
    --resource-group $resourceGroup `
    --issuer $issuerUrl `
    --subject $contractId

# See Note at https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster#create-the-federated-identity-credential
$sleepTime = 30
Write-Host "Waiting for $sleepTime seconds for federated identity credential to propagate after it is added"
Start-Sleep -Seconds $sleepTime


function Get-Assignee-Principal-Type {
    if ($env:GITHUB_ACTIONS -eq "true") {
        return "ServicePrincipal"
    }
    else {
        return "User"
    }
}