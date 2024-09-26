param(
    [string]$persona = "$env:MEMBER_NAME",

    [string]$privateDir = "./demo-resources.private",

    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datastoreDir = "$privateDir/datastores",
    [string]$scenario = "$(Split-Path $PSScriptRoot -Leaf)",
    [string]$datasinkPath = "$PSScriptRoot/datasink/$persona"
)

if (Test-Path -Path $datasinkPath)
{
    $dirs = Get-ChildItem -Path $datasinkPath -Directory -Name
    foreach ($dir in $dirs)
    {
        $datastoreName = "$scenario-$persona-$dir".ToLower()
        $datastoreFolder = "$datastoreDir/$datastoreName"

        Write-Host "Output from datastore '$datastoreName':"
        gzip -c -d $datastoreFolder/*.gz
    }
}
else
{
    Write-Host "No output available for persona '$persona' in scenario '$scenario'."
}
