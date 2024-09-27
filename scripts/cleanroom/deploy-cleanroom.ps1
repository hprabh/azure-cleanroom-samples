param(
    [Parameter(Mandatory = $true)]
    [string]$contractId,

    [string]$resourceGroup = "$env:RESOURCE_GROUP",
    [string]$cgsClient = "$env:PERSONA-client",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",
    [string]$artefactsDir = "$privateDir/$contractId-artefacts",

    [string]$cleanRoomName = "cleanroom-$contractId"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Write-Host -ForegroundColor Gray `
    "Deploying clean room for contract '$contractId'..." 

# Get the agreed upon ARM template for deployment.
(az cleanroom governance deployment template show `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --query "data") | Out-File "$artefactsDir/accepted-deployment-template.json"

# Deploy the clean room.
az deployment group create `
    --resource-group $resourceGroup `
    --name $cleanRoomName `
    --template-file "$artefactsDir/accepted-deployment-template.json"

Write-Host -ForegroundColor Yellow `
    "Deployed clean room '$cleanRoomName' for contract '$contractId' to '$resourceGroup'." 

