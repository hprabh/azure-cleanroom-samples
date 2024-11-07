param(
    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$samplesRoot = "/home/samples",
    [string]$secretDir = "$samplesRoot/demo-resources/secret",
    [string]$publicDir = "$samplesRoot/demo-resources/public",

    [string]$cgsClient = "$persona-client",
    [string]$ccfEndpoint = "$publicDir/ccfEndpoint"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

$ccfName = $persona + "-ccf"
$ccf = (az confidentialledger managedccfs list `
    --resource-group $resourceGroup `
    --query "[?name=='$ccfName']") | ConvertFrom-Json
if ($null -eq $ccf)
{
    Write-Log OperationStarted `
        "Creating consortium '$ccfName' in resource group '$resourceGroup'..."

    $memberCert = $secretDir + "/"+ $persona + "_cert.pem" # Created previously via the keygenerator-sh command.
    az confidentialledger managedccfs create `
        --name $ccfName `
        --resource-group $resourceGroup `
        --location "southcentralus" `
        --members "[{certificate:'$memberCert',identifier:'$persona'}]"
    $ccfUri = (az confidentialledger managedccfs show `
        --resource-group $resourceGroup `
        --name $ccfName `
        --query "properties.appUri" `
        --output tsv)
    Write-Log OperationCompleted `
        "Created consortium '$ccfName' ('$ccfUri')."
}
else {
    $ccfUri = $ccf.properties.appUri
    Write-Log Warning `
        "Connecting to consortium '$ccfName' ('$ccfUri')."
}

# Deploy client-side containers to interact with the governance service as the first member.
az cleanroom governance client deploy `
    --ccf-endpoint $ccfUri `
    --signing-cert $secretDir/$($persona)_cert.pem `
    --signing-key $secretDir/$($persona)_privk.pem `
    --name $cgsClient

# Accept the invitation and becomes an active member in the consortium.
az cleanroom governance member activate --governance-client $cgsClient

Write-Log OperationCompleted `
    "Joined consortium '$ccfUri' and deployed CGS client '$cgsClient'."

# Deploy governance service on the CCF instance.
az cleanroom governance service deploy --governance-client $cgsClient

# Share the CCF endpoint details.
$ccfUri | Out-File "$ccfEndpoint"
Write-Log OperationCompleted `
    "CCF configuration written to '$ccfEndpoint'."
