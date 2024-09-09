param(
    [ValidateSet("fabrikam", "contosso")]
    [string]$persona = "$env:MEMBER_NAME",
    [string]$cleanroomConfig = "./demo-resources.private/$env:RESOURCE_GROUP-analytics.generated.json",
    [string]$resourceConfig = "./demo-resources.private/$env:RESOURCE_GROUP.generated.json",
    [string]$datastoreConfig = "./demo-resources.private/datastores.config",
    [string]$datastoreDir = "./demo-resources.private/datastores",

)
$datastoreName = "analytics-$persona-input"
$datasourceName = "$persona-input"

$cleanroomConfigResult = Get-Content $cleanroomConfig | ConvertFrom-Json
$resourceConfigResult = Get-Content $resourceConfig | ConvertFrom-Json

az cleanroom config add-datasource-v2 `
    --cleanroom-config-file $cleanroomConfigResult.configFile `
    --name $datasourceName `
    --datastore-config $datastoreConfig `
    --datastore-name $datastoreName `
    --key-vault $resourceConfigResult.dek.kv.id `
    --identity $cleanroomConfigResult.mi.id
