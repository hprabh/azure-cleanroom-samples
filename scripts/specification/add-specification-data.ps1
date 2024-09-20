param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("analytics")]
    [string]$scenario,

    [string]$persona = "$env:MEMBER_NAME",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$privateDir = "./demo-resources.private",
    [string]$demosDir = "./demos",

    [string]$collabConfig = "$privateDir/$resourceGroup-analytics.generated.json",
    [string]$resourceConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$basePath = "$demosDir/$scenario/data/$persona"
)

if (-not (Test-Path -Path $basepath))
{
    Write-Host "No data publishing required for persona '$persona' in scenario '$scenario'."
    return
}

$collabConfigResult = Get-Content $collabConfig | ConvertFrom-Json
$resourceConfigResult = Get-Content $resourceConfig | ConvertFrom-Json

$dirs = Get-ChildItem -Path $basepath -Directory -Name
foreach ($dir in $dirs)
{
    $datastoreName = "$scenario-$persona-$dir".ToLower()
    $datasourceName = "$persona-$dir".ToLower()

    az cleanroom config add-datasource `
        --cleanroom-config $collabConfigResult.configFile `
        --name $datasourceName `
        --datastore-config $datastoreConfig `
        --datastore-name $datastoreName `
        --key-vault $resourceConfigResult.dek.kv.id `
        --identity "$persona-identity"
}