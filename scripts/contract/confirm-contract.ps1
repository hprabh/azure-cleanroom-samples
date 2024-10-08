param(
    [Parameter(Mandatory = $true)]
    [string]$contractId,

    [string]$cgsClient = "$env:PERSONA-client"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Write-Host "$($PSStyle.Formatting.CustomTableHeaderLabel)" `
    "Accepting contract '$contractId'..." 

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

Write-Host "$($PSStyle.Formatting.FormatAccent)" `
    "Accepted contract '$contractId'." 

