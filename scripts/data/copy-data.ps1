param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$scenario,
    [string]$persona = "$env:PERSONA",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",
    [string]$scenarioRoot = "$samplesRoot/scenario",

    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datastoreDir = "$privateDir/datastores",
    [string]$datasinkPath = "$scenarioRoot/$scenario/datasink/$persona"
)

if (Test-Path -Path $datasinkPath)
{
    $dirs = Get-ChildItem -Path $datasinkPath -Directory -Name
    foreach ($dir in $dirs)
    {
        $datastoreName = "$scenario-$persona-$dir".ToLower()
        az cleanroom datastore download `
            --name $datastoreName `
            --config $datastoreConfig `
            --dst $datastoreDir
        $dataDir = "$datastoreDir/$datastoreName"
        Write-Host -ForegroundColor Yellow `
            "Downloaded data for datasink '$($persona-$dir.ToLower())' ($datastoreName) " `
            "to '$dataDir'."
    }
}
else
{
    Write-Host -ForegroundColor Yellow `
        "No data download required for persona '$persona' in scenario '$scenario'."
}

