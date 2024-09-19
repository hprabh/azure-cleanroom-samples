param(
    [Parameter(Mandatory = $true)]
    [string]$contractId,

    [string]$cgsClient = "$env:MEMBER_NAME-client"
)

$contract = (az cleanroom governance contract show `
    --id $contractId `
    --governance-client $cgsClient | ConvertFrom-Json)

# Inspect the contract details that is capturing the storage, application container and identity details.
$contract.data

# Accept it.
az cleanroom governance contract vote `
    --id $contractId `
    --proposal-id $contract.proposalId `
    --action accept `
    --governance-client $cgsClient
