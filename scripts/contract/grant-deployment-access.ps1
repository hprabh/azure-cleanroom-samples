param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$demo,

    [Parameter(Mandatory = $true)]
    [string]$contractId,

    [string]$cgsClient = "$env:PERSONA-client",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$samplesRoot = "/home/samples",
    [string]$publicDir = "$samplesRoot/demo-resources.public",
    [string]$privateDir = "$samplesRoot/demo-resources.private",
    [string]$secretDir = "$samplesRoot/demo-resources.secret",

    [string]$oidcContainerName = "cgs-oidc",
    [string]$ccfEndpoint = (Get-Content "$publicDir/ccfEndpoint"),

    [string]$keyStore = "$secretDir/keys",
    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$environmentConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$contractConfig = "$privateDir/$resourceGroup-$demo.generated.json"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Write-Host -ForegroundColor Gray `
    "Granting access to resources required for '$demo' demo to deployments implementing " `
    "contract '$contractId'..." 

Import-Module $PSScriptRoot/../azure-helpers/azure-helpers.psm1 -Force -DisableNameChecking
$contractConfigResult = (Get-Content $contractConfig | ConvertFrom-Json)
$environmentConfigResult = Get-Content $environmentConfig | ConvertFrom-Json

#
# Create a KEK with SKR policy, wrap DEKs with the KEK and put in kv.
# TODO (phanic): Skip this for collaborator if they don't have a DEK.
#
az cleanroom config wrap-deks `
    --contract-id $contractId `
    --cleanroom-config $contractConfigResult.contractFragment `
    --datastore-config $datastoreConfig `
    --key-store $keyStore `
    --governance-client $cgsClient

#
# Setup managed identity access to storage/KV in collaborator tenant.
#
$managedIdentity = $contractConfigResult.mi

# Cleanroom needs both read/write permissions on storage account, hence assigning Storage Blob Data Contributor.
$role = "Storage Blob Data Contributor"
Write-Host -ForegroundColor Gray `
    "Assigning permission for '$role' to '$($managedIdentity.name)' on " `
    "storage account '$($environmentConfigResult.sa.name)'"
az role assignment create `
    --role "Storage Blob Data Contributor" `
    --scope $environmentConfigResult.sa.id `
    --assignee-object-id $managedIdentity.principalId `
    --assignee-principal-type ServicePrincipal
CheckLastExitCode

# KEK vault access.
$kekVault = $environmentConfigResult.kek.kv
if ($kekVault.type -eq "Microsoft.KeyVault/managedHSMs") {
    $role = "Managed HSM Crypto User"

    $roleAssignment = (az keyvault role assignment list `
            --assignee-object-id $managedIdentity.principalId `
            --hsm-name $kekVault.name `
            --role $role) | ConvertFrom-Json
    if ($roleAssignment.Length -eq 1) {
        Write-Host -ForegroundColor Yellow `
            "Skipping assignment as '$role' permission already exists for " `
            "'$($managedIdentity.name)' on mHSM '$($kekVault.name)'."
    }
    else {
        Write-Host -ForegroundColor Gray `
            "Assigning permissions for '$role' to '$($managedIdentity.name)' on " `
            "mHSM '$($kekVault.name)'"
        az keyvault role assignment create `
            --role $role `
            --scope "/" `
            --assignee-object-id $managedIdentity.principalId `
            --hsm-name $kekVault.name `
            --assignee-principal-type ServicePrincipal
        CheckLastExitCode
    }
}
elseif ($kekVault.type -eq "Microsoft.KeyVault/vaults") {
    $role = "Key Vault Crypto Officer"

    $roleAssignment = (az role assignment list `
            --assignee $managedIdentity.principalId `
            --scope $kekVault.id `
            --role $role) | ConvertFrom-Json
    if ($roleAssignment.Length -eq 1) {
        Write-Host -ForegroundColor Yellow `
            "Skipping assignment as '$role' permission already exists for " `
            "'$($managedIdentity.name)' on key vault '$($kekVault.name)'."
    }
    else {
        Write-Host -ForegroundColor Gray `
            "Assigning permissions for '$role' to '$($managedIdentity.name)' on " `
            "key vault '$($kekVault.name)'"
        az role assignment create `
            --role "Key Vault Crypto Officer" `
            --scope $kekVault.id `
            --assignee-object-id $managedIdentity.principalId `
            --assignee-principal-type ServicePrincipal
        CheckLastExitCode
    }
}

# DEK vault access.
$dekVault = $environmentConfigResult.dek.kv
$role = "Key Vault Secrets User"
Write-Host -ForegroundColor Gray `
    "Assigning permission for '$role' to '$($managedIdentity.name)' on " `
    "storage account '$($dekVault.name)'"
az role assignment create `
    --role  `
    --scope $dekVault.id `
    --assignee-object-id $managedIdentity.principalId `
    --assignee-principal-type ServicePrincipal
CheckLastExitCode

#
# Setup OIDC issuer for tenant.
#
$tenantId = az account show --query "tenantId" --output tsv
$tenantData = (az cleanroom governance oidc-issuer show `
        --governance-client $cgsClient `
        --query "tenantData" | ConvertFrom-Json)
if ($null -ne $tenantData -and $tenantData.tenantId -eq $tenantId) {
    $issuerUrl = $tenantData.issuerUrl
    Write-Host -ForegroundColor Yellow `
        "OIDC issuer already set for tenant '$tenantId' to '$issuerUrl'. Skipping!"
}
else {
    $oidcsa = $environmentConfigResult.oidcsa.name
    Write-Host -ForegroundColor Gray `
        "Setting up OIDC issuer for tenant '$tenantId' using storage account '$oidcsa'..."

    az storage account update --allow-blob-public-access true `
        --name $oidcsa
    Write-Host -ForegroundColor Yellow `
        "Enabled public blob access for '$oidcsa'."

    $sleepTime = 30
    Write-Host -ForegroundColor Gray `
        "Waiting for $sleepTime seconds for public blob access to be enabled..."
    Start-Sleep -Seconds $sleepTime

    Write-Host -ForegroundColor Gray `
        "Creating public access blob container '$oidcContainerName' in '$oidcsa'..."
    az storage container create `
        --name $oidcContainerName `
        --account-name $oidcsa `
        --public-access blob `
        --auth-mode login
    CheckLastExitCode
    Write-Host -ForegroundColor Yellow `
        "Created public access blob container '$oidcContainerName' in '$oidcsa'."

    Write-Host -ForegroundColor Gray `
        "Uploading openid-configuration to container '$oidcContainerName' in '$oidcsa'..."
    @"
{
"issuer": "https://$oidcsa.blob.core.windows.net/$oidcContainerName",
"jwks_uri": "https://$oidcsa.blob.core.windows.net/$oidcContainerName/openid/v1/jwks",
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
"@ | Out-File $privateDir/openid-configuration.json
    az storage blob upload `
        --container-name $oidcContainerName `
        --file $privateDir/openid-configuration.json `
        --name .well-known/openid-configuration `
        --account-name $oidcsa `
        --overwrite `
        --auth-mode login
    CheckLastExitCode

    Write-Host -ForegroundColor Gray `
        "Uploading jwks to container '$oidcContainerName' in '$oidcsa'..."
    $url = "$ccfEndpoint/app/oidc/keys"
    curl -s -k $url | jq | Out-File $privateDir/jwks.json
    az storage blob upload `
        --container-name $oidcContainerName `
        --file $privateDir/jwks.json `
        --name openid/v1/jwks `
        --account-name $oidcsa `
        --overwrite `
        --auth-mode login
    CheckLastExitCode

    Write-Host -ForegroundColor Gray `
        "Setting OIDC issuer for tenant '$tenantId'..."
    az cleanroom governance oidc-issuer set-issuer-url `
        --governance-client $cgsClient `
        --url "https://$oidcsa.blob.core.windows.net/$oidcContainerName"
    $tenantData = (az cleanroom governance oidc-issuer show `
            --governance-client $cgsClient `
            --query "tenantData" | ConvertFrom-Json)
    $issuerUrl = $tenantData.issuerUrl

    Write-Host -ForegroundColor Yellow `
        "Set OIDC issuer for tenant '$tenantId' to '$issuerUrl'."
}

#
# Setup federated credential on managed identity.
#
Write-Host -ForegroundColor Gray `
    "Setting up federation on managed identity '$($managedIdentity.name)' for " `
    "issuer '$issuerUrl' and subject '$contractId'..."
az identity federated-credential create `
    --name "$contractId-federation" `
    --identity-name $managedIdentity.name `
    --resource-group $resourceGroup `
    --issuer $issuerUrl `
    --subject $contractId

# See Note at https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster#create-the-federated-identity-credential
$sleepTime = 30
Write-Host -ForegroundColor Gray `
    "Waiting for $sleepTime seconds for federated identity credential to propagate..."
Start-Sleep -Seconds $sleepTime

Write-Host -ForegroundColor Yellow `
    "Granted access to resources required for '$demo' demo to deployments implementing " `
    "contract '$contractId' through federation on managed identity '$($managedIdentity.name)'." 