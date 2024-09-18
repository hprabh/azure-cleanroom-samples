param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("analytics")]
    [string]$scenario,

    [string]$persona = "$env:MEMBER_NAME",
    [string]$cleanroomConfig = "./demo-resources.private/$env:RESOURCE_GROUP-$scenario.generated.json",
    [string]$resourceConfig = "./demo-resources.private/$env:RESOURCE_GROUP.generated.json",
    [string]$datastoreConfig = "./demo-resources.private/datastores.config",
    [string]$keysDir = "./demo-resources.secret/keys"
)

$cleanroomConfigResult = Get-Content $cleanroomConfig | ConvertFrom-Json
$resourceConfigResult = Get-Content $resourceConfig | ConvertFrom-Json

# $result below refers to the output of the prepare-resources.ps1 that was run earlier.
az cleanroom config set-logging `
    --cleanroom-config-file $cleanroomConfigResult.configFile `
    --datastore-config $datastoreConfig `
    --datastore-keystore $keysDir `
    --storage-account $resourceConfigResult.sa.id `
    --identity "$persona-identity" `
    --key-vault $resourceConfigResult.dek.kv.id `
    --encryption-mode CPK

az cleanroom config set-telemetry `
    --cleanroom-config-file $cleanroomConfigResult.configFile `
    --datastore-config $datastoreConfig `
    --datastore-keystore $keysDir `
    --storage-account $resourceConfigResult.sa.id `
    --identity "$persona-identity" `
    --key-vault $resourceConfigResult.dek.kv.id `
    --encryption-mode CPK