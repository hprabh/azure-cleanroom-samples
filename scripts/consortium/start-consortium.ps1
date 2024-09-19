param(
    [string]$memberName = "$env:MEMBER_NAME",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$secretDir = "./demo-resources.secret",
    [string]$publicDir = "./demo-resources.public",

    [string]$cgsClient = "$memberName-client"
)

$ccfName = $memberName + "-ccf"
$memberCert = $secretDir + "/"+ $memberName +"_cert.pem" # Created previously via the keygenerator-sh command.
az confidentialledger managedccfs create `
    --name $ccfName `
    --resource-group $resourceGroup `
    --location "southcentralus" `
    --members "[{certificate:'$memberCert',identifier:'$memberName'}]"
$ccfEndpoint = (az confidentialledger managedccfs show `
    --resource-group $resourceGroup `
    --name $ccfName `
    --query "properties.appUri" `
    --output tsv)

# Share the CCF endpoint details.
$ccfEndpoint > "$publicDir/ccfEndpoint"

# Deploy client-side containers to interact with the governance service as the first member.
az cleanroom governance client deploy `
  --ccf-endpoint $ccfEndpoint `
  --signing-cert $secretDir/$($memberName)_cert.pem `
  --signing-key $secretDir/$($memberName)_privk.pem `
  --name $cgsClient

# Activate membership.
az cleanroom governance member activate --governance-client $cgsClient

# Deploy governance service on the CCF instance.
az cleanroom governance service deploy --governance-client $cgsClient