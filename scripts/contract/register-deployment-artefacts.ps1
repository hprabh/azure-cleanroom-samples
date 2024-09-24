param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$scenario,

    [ValidateSet("cached", "generate", "generate-debug", "allow-all")]
    [string]$securityPolicy = "cached",

    [string[]]$collaborators = ('litware', 'fabrikam', 'contosso'),

    [string]$cgsClient = "$env:MEMBER_NAME-client",

    [string]$publicDir = "./demo-resources.public",

    [string]$cleanroomConfig = "$publicDir/finalized-$scenario.config",
    [string]$contractId = "collab-$scenario",
    [string]$artefactDir = "$publicDir/$contractId"
)

mkdir $artefactDir

az cleanroom governance deployment generate `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --securityPolicy $securityPolicy `
    --output-dir $artefactDir

az cleanroom governance deployment template propose `
    --template-file $artefactDir/cleanroom-arm-template.json `
    --contract-id $contractId `
    --governance-client $cgsClient

az cleanroom governance deployment policy propose `
    --policy-file $artefactDir/cleanroom-governance-policy.json `
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
