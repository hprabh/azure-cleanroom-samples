param(
    [Parameter(Mandatory = $true)]
    [string]$contractId,

    [string]$resourceGroup = "$env:RESOURCE_GROUP",
    [string]$cgsClient = "$env:MEMBER_NAME-client",

    [string]$publicDir = "./demo-resources.public",

    [string]$cleanRoomName = "cleanroom-$contractId"
)

# Get the agreed upon ARM template for deployment.
(az cleanroom governance deployment template show `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --query "data") | Out-File "$publicDir/$cleanRoomName-deployment-template.json"

# Deploy the clean room.
az deployment group create `
    --resource-group $resourceGroup `
    --name $cleanRoomName `
    --template-file "$publicDir/$cleanRoomName-deployment-template.json"