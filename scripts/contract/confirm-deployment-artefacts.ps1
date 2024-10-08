param(
    [Parameter(Mandatory = $true)]
    [string]$contractId,

    [string]$cgsClient = "$env:PERSONA-client"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Write-Host "$($PSStyle.Formatting.CustomTableHeaderLabel)" `
    "Accepting deployment artefacts for '$contractId'..." 

# Vote on the proposed deployment template.
$proposalId = az cleanroom governance deployment template show `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --query "proposalIds[0]" `
    --output tsv
Write-Host "$($PSStyle.Dim)$($PSStyle.Italic)" `
    "Accepting deployment template proposal '$proposalId'..."
az cleanroom governance proposal show-actions `
    --proposal-id $proposalId `
    --query "actions[0].args.spec.data" `
    --governance-client $cgsClient
# TODO (phanic): Logic to showcase template verification is pending.
az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $cgsClient
Write-Host "$($PSStyle.Formatting.FormatAccent)" `
    "Accepted deployment template for '$contractId'."

# Vote on the proposed cce policy.
$proposalId = az cleanroom governance deployment policy show `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --query "proposalIds[0]" `
    --output tsv
Write-Host "$($PSStyle.Dim)$($PSStyle.Italic)" `
    "Accepting deployment policy proposal '$proposalId'..."
az cleanroom governance proposal show-actions `
    --proposal-id $proposalId `
    --query "actions[0].args" `
    --governance-client $cgsClient
# TODO (phanic): Logic to showcase policy verification is pending.
az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $cgsClient
Write-Host "$($PSStyle.Formatting.FormatAccent)" `
    "Accepted deployment policy for '$contractId'."

# Vote on the enable logging proposal.
$proposalId = az cleanroom governance contract runtime-option get `
    --option logging `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --query "proposalIds[0]" `
    --output tsv
Write-Host "$($PSStyle.Dim)$($PSStyle.Italic)" `
    "Accepting enable logging proposal '$proposalId'..."
az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $cgsClient
Write-Host "$($PSStyle.Formatting.FormatAccent)" `
    "Accepted enabling application telemetry for '$contractId'."

# Vote on the enable telemetry proposal.
$proposalId = az cleanroom governance contract runtime-option get `
    --option telemetry `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --query "proposalIds[0]" `
    --output tsv
Write-Host "$($PSStyle.Dim)$($PSStyle.Italic)" `
    "Accepting enable telemetry proposal '$proposalId'..."
az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $cgsClient
Write-Host "$($PSStyle.Formatting.FormatAccent)" `
    "Accepted enabling infrastructure telemetry for '$contractId'."
