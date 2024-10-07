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
        Write-Host -ForegroundColor DarkGray `
            "Enumerated datasink '$datasinkName' in '$datasinkPath'..."

        $datastoreName = "$demo-$persona-$dir".ToLower()
        # TODO (phanic): Understand why this is being copied into a nested folder.
        $datastoreFolder = "$datastoreDir/$datastoreName/$datastoreName"
        Write-Host -ForegroundColor Yellow `
            "Output from datastore '$datastoreName':"
        Write-Host -ForegroundColor DarkGray `
            "-----BEGIN OUTPUT-----"
        gzip -c -d $datastoreFolder/*.gz
        Write-Host -ForegroundColor DarkGray `
            "-----END OUTPUT-----"
    }
}
else
{
    Write-Host -ForegroundColor Yellow `
        "No output available for persona '$persona' in demo '$demo'."
}
