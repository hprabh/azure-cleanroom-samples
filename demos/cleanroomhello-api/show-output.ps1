param(
    [string]$persona = "$env:MEMBER_NAME",

    [string]$privateDir = "./demo-resources.private",
    [string]$demosDir = "./demos",

    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datastoreDir = "$privateDir/datastores",
    [string]$scenario = "$(Split-Path $PSScriptRoot -Leaf)",
    [string]$datasinkPath = "$demosDir/$scenario/datasink/$persona"
)

Write-Host "No output available for persona '$persona' in scenario '$scenario'."
