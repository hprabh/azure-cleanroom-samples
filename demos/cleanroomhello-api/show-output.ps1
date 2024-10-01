param(
    [string]$persona = "$env:PERSONA",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",
    [string]$demosRoot = "$samplesRoot/demos",

    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datastoreDir = "$privateDir/datastores",
    [string]$demo = "$(Split-Path $PSScriptRoot -Leaf)",
    [string]$datasinkPath = "$demosRoot/$demo/datasink/$persona"
)

Write-Host -ForegroundColor Yellow `
    "No output available for persona '$persona' in demo '$demo'."
