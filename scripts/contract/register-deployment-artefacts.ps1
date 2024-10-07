param(
    [Parameter(Mandatory = $true)]
    [string]$contractId,

    [ValidateSet("cached", "generate", "generate-debug", "allow-all")]
    [string]$securityPolicy = "cached",

    [string]$cgsClient = "$env:PERSONA-client",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",
    [string]$artefactsDir = "$privateDir/$contractId-artefacts"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Write-Host -ForegroundColor DarkGray `
    "Generating deployment artefacts for contract '$contractId' in '$artefactsDir'..." 

mkdir -p $artefactsDir
az cleanroom governance deployment generate `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --security-policy-creation-option $securityPolicy `
    --output-dir $artefactsDir

Write-Host -ForegroundColor DarkGray `
    "Proposing deployment artefacts for contract '$contractId' to the consortium..." 

az cleanroom governance deployment template propose `
    --template-file $artefactsDir/cleanroom-arm-template.json `
    --contract-id $contractId `
    --governance-client $cgsClient

az cleanroom governance deployment policy propose `
    --policy-file $artefactsDir/cleanroom-governance-policy.json `
    --contract-id $contractId `
    --governance-client $cgsClient

# Propose enabling log and telemetry collection during cleanroom execution.
az cleanroom governance contract runtime-option propose `
    --option logging `
    --action enable `
    --contract-id $contractId `
    --governance-client $cgsClient

az cleanroom governance contract runtime-option propose `
    --option telemetry `
    --action enable `
    --contract-id $contractId `
    --governance-client $cgsClient

Write-Host -ForegroundColor Yellow `
    "Proposed deployment artefacts for contract '$contractId' to the consortium." 

