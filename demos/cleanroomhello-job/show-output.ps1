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
        Write-Host "$($PSStyle.Dim)$($PSStyle.Italic)" `
            "Enumerated datasink '$datasinkName' in '$datasinkPath'..."

        $datastoreName = "$demo-$persona-$dir".ToLower()
        # TODO (phanic): Understand why this is being copied into a nested folder.
        $datastoreFolder = "$datastoreDir/$datastoreName/**"
        Write-Host "$($PSStyle.Formatting.FormatAccent)" `
            "Output from datastore '$datastoreName':"
        Write-Host "$($PSStyle.Dim)$($PSStyle.Italic)" `
            "-----BEGIN OUTPUT-----" `
            "$($PSStyle.Reset)"
        gzip -c -d $datastoreFolder/*.gz
        Write-Host "$($PSStyle.Dim)$($PSStyle.Italic)" `
            "-----END OUTPUT-----"
    }
}
else
{
    Write-Host "$($PSStyle.Formatting.ErrorAccent)" `
        "No output available for persona '$persona' in demo '$demo'."
}
