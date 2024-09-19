param(
    [Parameter(Mandatory = $true)]
    [string]$contractId,

    [string]$cgsClient = "$env:MEMBER_NAME-client"
)

Write-Host -ForegroundColor Yellow "Placeholder: Logic to showcase proposal verification is pending"

# Vote on the proposed deployment template.
$proposalId = az cleanroom governance deployment template show `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --query "proposalIds[0]" `
    --output tsv

Write-Host -ForegroundColor Yellow "Accepting deployment template ($proposalId)..."
az cleanroom governance proposal show-actions `
    --proposal-id $proposalId `
    --query "actions[0].args.spec.data" `
    --governance-client $cgsClient
az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $cgsClient

# Vote on the proposed cce policy.
$proposalId = az cleanroom governance deployment policy show `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --query "proposalIds[0]" `
    --output tsv

Write-Host -ForegroundColor Yellow "Accepting deployment policy ($proposalId)..."
az cleanroom governance proposal show-actions `
    --proposal-id $proposalId `
    --query "actions[0].args" `
    --governance-client $cgsClient
az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $cgsClient

# Vote on the enable logging proposal.
$proposalId = az cleanroom governance contract runtime-option get `
    --option logging `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --query "proposalIds[0]" `
    --output tsv

Write-Host -ForegroundColor Yellow "Accepting enable logging ($proposalId)..."
az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $cgsClient

# Vote on the enable telemetry proposal.
$proposalId = az cleanroom governance contract runtime-option get `
    --option telemetry `
    --contract-id $contractId `
    --governance-client $cgsClient `
    --query "proposalIds[0]" `
    --output tsv

Write-Host -ForegroundColor Yellow "Accepting enable telemetry ($proposalId)..."
az cleanroom governance proposal vote `
    --proposal-id $proposalId `
    --action accept `
    --governance-client $cgsClient
