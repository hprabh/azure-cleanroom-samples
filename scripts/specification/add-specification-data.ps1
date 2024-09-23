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
    [string]$datasourcePath = "$demosDir/$scenario/datasource/$persona",
    [string]$datasinkPath = "$demosDir/$scenario/datasink/$persona"
)

$collabConfigResult = Get-Content $collabConfig | ConvertFrom-Json
$resourceConfigResult = Get-Content $resourceConfig | ConvertFrom-Json

if (Test-Path -Path $datasourcePath)
{
    $dirs = Get-ChildItem -Path $datasourcePath -Directory -Name
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
}
else
{
    Write-Host "No datasource required for persona '$persona' in scenario '$scenario'."
}


if (Test-Path -Path $datasinkPath)
{
    $dirs = Get-ChildItem -Path $datasinkPath -Directory -Name
    foreach ($dir in $dirs)
    {
        $datastoreName = "$scenario-$persona-$dir".ToLower()
        $datasinkName = "$persona-$dir".ToLower()
    
        az cleanroom config add-datasink `
            --cleanroom-config $collabConfigResult.configFile `
            --name $datasinkName `
            --datastore-config $datastoreConfig `
            --datastore-name $datastoreName `
            --key-vault $resourceConfigResult.dek.kv.id `
            --identity "$persona-identity"
    }
}
else
{
    Write-Host "No datasink required for persona '$persona' in scenario '$scenario'."
}
