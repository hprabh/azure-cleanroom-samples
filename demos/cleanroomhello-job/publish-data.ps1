param(
    [ValidateSet("fabrikam")]
    [string]$persona = "$env:MEMBER_NAME",

    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$privateDir = "./demo-resources.private",
    [string]$secretDir = "./demo-resources.secret",
    [string]$sa = "",

    [string]$resourceConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$keyStore = "$secretDir/keys",
    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datastoreDir = "$privateDir/datastores"
)

if (-not (("fabrikam") -contains $persona))
{
    Write-Host "No action required for persona '$persona' in this scenario."
    return
}

if ($sa -eq "")
{
    $initResult = Get-Content $resourceConfig | ConvertFrom-Json
    $sa = $initResult.sa.id
}

$datastoreName = "cleanroomhello-job-$persona-input"

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
