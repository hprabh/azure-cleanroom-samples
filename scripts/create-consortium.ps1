param(
    [string]$memberName = "$env:MEMBER_NAME",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",
    [string]$secretsFolder = "./demo-resources.secret",
    [string]$publicFolder = "./demo-resources.public"
)

$ccfName = $memberName + "-ccf"
$memberCert = $secretsFolder + "/"+ $memberName +"_cert.pem" # Created previously via the keygenerator-sh command.
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
$ccfEndpoint > "$publicFolder/ccfEndpoint"

# Deploy client-side containers to interact with the governance service as the first member.
az cleanroom governance client deploy `
  --ccf-endpoint $ccfEndpoint `
  --signing-cert $secretsFolder/$($memberName)_cert.pem `
  --signing-key $secretsFolder/$($memberName)_privk.pem `
  --name "$memberName-client"

# Activate membership.
az cleanroom governance member activate --governance-client "$memberName-client"

# Deploy governance service on the CCF instance.
az cleanroom governance service deploy --governance-client "$memberName-client"