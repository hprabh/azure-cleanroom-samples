param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("analytics")]
    [string]$scenario,

    [string]$persona = "$env:MEMBER_NAME",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$privateDir = "./demo-resources.private",
    [string]$secretDir = "./demo-resources.secret",
    [string]$demosDir = "./demos",
    [string]$sa = "",

    [string]$resourceConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$keyStore = "$secretDir/keys",
    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datastoreDir = "$privateDir/datastores",
    [string]$datasourcePath = "$demosDir/$scenario/datasource/$persona",
    [string]$datasinkPath = "$demosDir/$scenario/datasink/$persona"
)

if (-not (Test-Path -Path $datasourcePath))
{
    Write-Host "No action required for persona '$persona' in scenario '$scenario'."
    return
}

if (-not (("fabrikam", "contosso") -contains $persona))
{
    Write-Host "No action required for persona '$persona' in this scenario."
    return
}

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
