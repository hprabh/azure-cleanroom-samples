param(
    [ValidateSet("fabrikam", "contosso")]
    [string]$persona = "$env:MEMBER_NAME",

    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$privateDir = "./demo-resources.private",

    [string]$cleanroomConfig = "$privateDir/$resourceGroup-analytics.generated.json",
    [string]$resourceConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datastoreDir = "$privateDir/datastores"
)

if (-not (("fabrikam", "contosso") -contains $persona))
{
    Write-Host "No action required for persona '$persona' in this scenario."
    return
}

$datastoreName = "analytics-$persona-input"
$datasourceName = "$persona-input"

$cleanroomConfigResult = Get-Content $cleanroomConfig | ConvertFrom-Json
$resourceConfigResult = Get-Content $resourceConfig | ConvertFrom-Json

az cleanroom config add-datasource `
    --cleanroom-config $cleanroomConfigResult.configFile `
    --name $datasourceName `
    --datastore-config $datastoreConfig `
    --datastore-name $datastoreName `
    --key-vault $resourceConfigResult.dek.kv.id `
    --identity "$persona-identity"
