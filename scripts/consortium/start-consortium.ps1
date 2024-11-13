param(
    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",
    [string]$resourceGroupLocation = "$env:RESOURCE_GROUP_LOCATION",

    [string]$samplesRoot = "/home/samples",
    [string]$secretDir = "$samplesRoot/demo-resources/secret",
    [string]$privateDir = "$samplesRoot/demo-resources/private",
    [string]$publicDir = "$samplesRoot/demo-resources/public",

    [string]$environmentConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$ccfProviderClient = "azure-cleanroom-samples-ccf-provider",
    [string]$cgsClient = "$persona-client",
    [string]$ccfEndpoint = "$publicDir/ccfEndpoint"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

$initResult = Get-Content $environmentConfig | ConvertFrom-Json
$sa = $initResult.ccfsa.id

$ccfName = $persona + "-ccf"

#
# Create a CCF instance.
#
if (!(Test-Path -Path "$privateDir/ccfProviderConfig.json"))
{
    @"
{
    "location": "$resourceGroupLocation",
    "subscriptionId": "$subscriptionId",
    "resourceGroupName": "$resourceGroup",
    "azureFiles": {
        "storageAccountId": "$sa"
    }
}
"@  | Out-File $privateDir/ccfProviderConfig.json
}

$ccf = (az cleanroom ccf network show `
    --name $ccfName `
    --provider-config $privateDir/ccfProviderConfig.json `
    --provider-client $ccfProviderClient | ConvertFrom-Json)
if ($null -eq $ccf)
{
    Write-Log OperationStarted `
        "Creating consortium '$ccfName' in resource group '$resourceGroup'..."

    $memberCert = $secretDir + "/"+ $persona + "_cert.pem"
    $encryptionCert = $secretDir + "/"+ $persona + "_enc_pubk.pem"

    @"
[{
    "certificate": "$memberCert",
    "encryptionPublicKey": "$encryptionCert",
    "memberData": {
        "identifier": "ccf-operator",
        "is_operator": true
    }
},
{
    "certificate": "$memberCert",
    "memberData": {
        "identifier": "$persona"
    }
}]
"@ | Out-File $privateDir/ccfMembers.json

    $ccf = (az cleanroom ccf network create `
        --name $ccfName `
        --node-count 1 `
        --node-log-level "Debug" `
        --security-policy-creation-option "allow-all" `
        --infra-type 'caci' `
        --members $privateDir/ccfMembers.json `
        --provider-config $privateDir/ccfProviderConfig.json `
        --provider-client $ccfProviderClient | ConvertFrom-Json)
    $ccfUri = $ccf.endpoint

    Write-Log OperationCompleted `
        "Created CCF network '$ccfName' ('$ccfUri')."
}
else {
    $ccfUri = $ccf.endpoint
    Write-Log Warning `
        "Connecting CCF network '$ccfName' ('$ccfUri')."
}

$response = (curl "$ccfUri/node/network" -k --silent | ConvertFrom-Json)
# Trimming an extra new-line character added to the cert.
$serviceCert = $response.service_certificate.TrimEnd("`n")
$serviceCert | Out-File "$publicDir/${ccfName}_service_cert.pem"

# Deploy client-side containers to interact with the governance service as the first member.
az cleanroom governance client deploy `
    --ccf-endpoint $ccfUri `
    --signing-cert $secretDir/$($persona)_cert.pem `
    --signing-key $secretDir/$($persona)_privk.pem `
    --service-cert $publicDir/$($ccfName)_service_cert.pem `
    --name $cgsClient

# Accept the invitation and becomes an active member in the consortium.
az cleanroom governance member activate --governance-client $cgsClient

Write-Log OperationCompleted `
    "Joined consortium '$ccfUri' and deployed CGS client '$cgsClient'."

# Deploy governance service on the CCF instance.
az cleanroom governance service deploy --governance-client $cgsClient

# Share the CCF endpoint details.
$result = @{
    url = $ccfUri
    serviceCert = $serviceCert
}
$result | Out-File "$ccfEndpoint"
Write-Log OperationCompleted `
    "CCF configuration written to '$ccfEndpoint'."
