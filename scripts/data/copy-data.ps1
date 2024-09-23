param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("analytics")]
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
        $datastoreFolder = "$datastoreDir/$datastoreName"

        az cleanroom datastore download `
            --name $datastoreName `
            --config $datastoreConfig `
            --dst $datastoreFolder
    }
}
else
{
    Write-Host "No data download required for persona '$persona' in scenario '$scenario'."
}

