param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("analytics")]
    [string]$scenario,

    [string]$persona = "$env:MEMBER_NAME",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$privateDir = "./demo-resources.private",
    [string]$secretDir = "./demo-resources.secret",

    [string]$cleanroomConfig = "$privateDir/$resourceGroup-$scenario.generated.json",
    [string]$resourceConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$keysDir = "$secretDir/keys"
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