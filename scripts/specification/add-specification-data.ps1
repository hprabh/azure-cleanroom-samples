param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$demo,

    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",
    [string]$demosRoot = "$samplesRoot/demos",

    [string]$contractConfig = "$privateDir/$resourceGroup-$demo.generated.json",
    [string]$environmentConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datasourcePath = "$demosRoot/$demo/datasource/$persona",
    [string]$datasinkPath = "$demosRoot/$demo/datasink/$persona"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$contractConfigResult = Get-Content $contractConfig | ConvertFrom-Json
$environmentConfigResult = Get-Content $environmentConfig | ConvertFrom-Json

Write-Host "$($PSStyle.Formatting.CustomTableHeaderLabel)" `
    "Adding datasources and datasinks for '$persona' in the '$demo' demo to " `
    "'$($contractConfigResult.contractFragment)'..."

if (Test-Path -Path $datasourcePath)
{
    $dirs = Get-ChildItem -Path $datasourcePath -Directory -Name
    foreach ($dir in $dirs)
    {
        $datastoreName = "$demo-$persona-$dir".ToLower()
        $datasourceName = "$persona-$dir".ToLower()
        az cleanroom config add-datasource `
            --cleanroom-config $contractConfigResult.contractFragment `
            --name $datasourceName `
            --datastore-config $datastoreConfig `
            --datastore-name $datastoreName `
            --key-vault $environmentConfigResult.dek.kv.id `
            --identity "$persona-identity"
        Write-Host "$($PSStyle.Formatting.FormatAccent)" `
            "Added datasource '$datasourceName' ($datastoreName)."
    }
}
else
{
    Write-Host "$($PSStyle.Formatting.ErrorAccent)" `
        "No datasource required for persona '$persona' in demo '$demo'."
}

if (Test-Path -Path $datasinkPath)
{
    $dirs = Get-ChildItem -Path $datasinkPath -Directory -Name
    foreach ($dir in $dirs)
    {
        $datastoreName = "$demo-$persona-$dir".ToLower()
        $datasinkName = "$persona-$dir".ToLower()
        az cleanroom config add-datasink `
            --cleanroom-config $contractConfigResult.contractFragment `
            --name $datasinkName `
            --datastore-config $datastoreConfig `
            --datastore-name $datastoreName `
            --key-vault $environmentConfigResult.dek.kv.id `
            --identity "$persona-identity"
        Write-Host "$($PSStyle.Formatting.FormatAccent)" `
            "Added datasink '$datasinkName' ($datastoreName)."
    }
}
else
{
    Write-Host "$($PSStyle.Formatting.ErrorAccent)" `
        "No datasink required for persona '$persona' in demo '$demo'."
}
