param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$demo,
    [string]$persona = "$env:PERSONA",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",
    [string]$demosRoot = "$samplesRoot/demos",

    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datastoreDir = "$privateDir/datastores",
    [string]$datasinkPath = "$demosRoot/$demo/datasink/$persona"
)

if (Test-Path -Path $datasinkPath)
{
    $dirs = Get-ChildItem -Path $datasinkPath -Directory -Name
    foreach ($dir in $dirs)
    {
        $datastoreName = "$demo-$persona-$dir".ToLower()

        # TODO (phanic): Understand why this is being copied into a nested folder.
        az cleanroom datastore download `
            --name $datastoreName `
            --config $datastoreConfig `
            --dst $datastoreDir
        $dataDir = "$datastoreDir/$datastoreName"
        Write-Host -ForegroundColor Yellow `
            "Downloaded data for datasink '$persona-$dir' ($datastoreName) " `
            "to '$dataDir'."
    }
}
else
{
    Write-Host -ForegroundColor Yellow `
        "No data download required for persona '$persona' in demo '$demo'."
}

