param(
    [string]$persona = "$env:PERSONA",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",

    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datastoreDir = "$privateDir/datastores",
    [string]$demo = "$(Split-Path $PSScriptRoot -Leaf)",
    [string]$datasinkPath = "$PSScriptRoot/datasink/$persona"
)

if (Test-Path -Path $datasinkPath)
{
    $dirs = Get-ChildItem -Path $datasinkPath -Directory -Name
    foreach ($dir in $dirs)
    {
        $datasinkName = "$persona-$dir".ToLower()
        Write-Host -ForegroundColor Gray `
            "Enumerated datasink '$datasinkName' in '$datasinkPath'..."

        $datastoreName = "$demo-$persona-$dir".ToLower()
        $datastoreFolder = "$datastoreDir/$datastoreName"
        Write-Host -ForegroundColor Yellow `
            "Output from datastore '$datastoreName':"
        Write-Host -ForegroundColor Gray `
            "-----BEGIN OUTPUT-----"
        gzip -c -d $datastoreFolder/*.gz
        Write-Host -ForegroundColor Gray `
            "-----END OUTPUT-----"
    }
}
else
{
    Write-Host -ForegroundColor Yellow `
        "No output available for persona '$persona' in demo '$demo'."
}
