param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$scenario,
    [string]$persona = "$env:MEMBER_NAME",

    [string]$privateDir = "./demo-resources.private",
    [string]$demosDir = "./demos",

    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datastoreDir = "$privateDir/datastores",
    [string]$datasinkPath = "$demosDir/$scenario/datasink/$persona"
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
    }
}
else
{
    Write-Host "No data download required for persona '$persona' in scenario '$scenario'."
}

