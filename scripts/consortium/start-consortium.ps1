param(
    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$samplesRoot = "/home/samples",
    [string]$secretDir = "$samplesRoot/demo-resources.secret",
    [string]$publicDir = "$samplesRoot/demo-resources.public",

    [string]$cgsClient = "$persona-client",
    [string]$ccfConfig = "$publicDir/ccfEndpoint"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$ccfName = $persona + "-ccf"
Write-Host -ForegroundColor DarkGray `
    "Creating consortium '$ccfName' in resource group '$resourceGroup'..."

$memberCert = $secretDir + "/"+ $persona +"_cert.pem" # Created previously via the keygenerator-sh command.
az confidentialledger managedccfs create `
    --name $ccfName `
    --resource-group $resourceGroup `
    --location "southcentralus" `
    --members "[{certificate:'$memberCert',identifier:'$persona'}]"
$ccfEndpoint = (az confidentialledger managedccfs show `
    --resource-group $resourceGroup `
    --name $ccfName `
    --query "properties.appUri" `
    --output tsv)
Write-Host -ForegroundColor Yellow `
    "Created consortium '$ccfName' ('$ccfEndpoint')."

# Deploy client-side containers to interact with the governance service as the first member.
az cleanroom governance client deploy `
    --ccf-endpoint $ccfEndpoint `
    --signing-cert $secretDir/$($persona)_cert.pem `
    --signing-key $secretDir/$($persona)_privk.pem `
    --name $cgsClient

# Accept the invitation and becomes an active member in the consortium.
az cleanroom governance member activate --governance-client $cgsClient

Write-Host -ForegroundColor Yellow `
    "Joined consortium '$ccfEndpoint' and deployed CGS client '$cgsClient'."

# Deploy governance service on the CCF instance.
az cleanroom governance service deploy --governance-client $cgsClient

# Share the CCF endpoint details.
$ccfEndpoint | Out-File "$ccfConfig"
Write-Host -ForegroundColor Yellow `
    "CCF configuration written to '$ccfConfig'."
