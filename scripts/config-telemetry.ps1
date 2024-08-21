param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("analytics")]
    [string]$scenario,

    [string]$cleanroomConfig = "./demo-resources.private/$env:RESOURCE_GROUP-$scenario.generated.json",
    [string]$resourceConfig = "./demo-resources.private/$env:RESOURCE_GROUP.generated.json",
    [string]$datastoreConfig = "./demo-resources.private/datastores.config",
    [string]$keysDir = "./demo-resources.secret/keys",
)

$cleanroomConfigResult = Get-Content $cleanroomConfig | ConvertFrom-Json
$resourceConfigResult = Get-Content $resourceConfig | ConvertFrom-Json

# $result below refers to the output of the prepare-resources.ps1 that was run earlier.
az cleanroom config set-logging-v2 `
    --cleanroom-config-file $cleanroomConfigResult.configFile `
    --datastore-config $datastoreConfig `
    --datastore-keystore $keysDir `
    --storage-account $resourceConfigResult.sa.id `
    --identity $cleanroomConfigResult.mi.id `
    --key-vault $resourceConfigResult.dek.kv.id

az cleanroom config set-telemetry-v2 `
    --cleanroom-config-file $cleanroomConfigResult.configFile `
    --datastore-config $datastoreConfig `
    --datastore-keystore $keysDir `
    --storage-account $resourceConfigResult.sa.id `
    --identity $cleanroomConfigResult.mi.id `
    --key-vault $resourceConfigResult.dek.kv.id