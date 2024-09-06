param(
    [ValidateSet("fabrikam", "contosso")]
    [string]$persona = "$env:MEMBER_NAME",
    [string]$sa = "",
    [string]$resourceConfig = "./demo-resources.private/$env:RESOURCE_GROUP.generated.json",
    [string]$keyStore = "./demo-resources.secret/keys",
    [string]$datastoreConfig = "./demo-resources.private/datastores.config",
    [string]$datastoreDir = "./demo-resources.private/datastores"
)

if ($sa -eq "")
{
    $initResult = Get-Content $resourceConfig | ConvertFrom-Json
    $sa = $initResult.sa.id
}

$datastoreName = "analytics-$persona-input"

az cleanroom datastore add `
    --name $datastoreName `
    --config $datastoreConfig `
    --keystore $keyStore `
    --encryption-mode CPK `
    --backingstore-type Azure_BlobStorage `
    --backingstore-id $sa

$datastoreFolder = "$datastoreDir/$datastoreName"
mkdir -p $datastoreFolder

cp -r "$PSScriptRoot/data/$persona/" $datastoreFolder

az cleanroom datastore upload `
    --name $datastoreName `
    --config $datastoreConfig `
    --src $datastoreFolder
