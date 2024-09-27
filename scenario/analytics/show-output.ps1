param(
    [string]$persona = "$env:PERSONA",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",
    [string]$scenarioRoot = "$samplesRoot/scenario",

    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datastoreDir = "$privateDir/datastores",
    [string]$scenario = "$(Split-Path $PSScriptRoot -Leaf)",
    [string]$datasinkPath = "$scenarioRoot/$scenario/datasink/$persona"
)

Write-Host -ForegroundColor Yellow `
    "No output available for persona '$persona' in scenario '$scenario'."
