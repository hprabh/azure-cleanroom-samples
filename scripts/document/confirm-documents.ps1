param(
    [Parameter(Mandatory = $true)]
    [string]$contractId,

    [string]$cgsClient = "$env:PERSONA-client"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

Write-Log OperationStarted `
    "Accepting documents for '$contractId'..." 

Write-Log Verbose `
    "Enumerating all documents..."
$documentIds = @(az cleanroom governance document show `
    --governance-client $cgsClient `
    --query "[*].id" `
    --output json | ConvertFrom-Json)

foreach ($documentId in $documentIds)
{
    Write-Log Verbose `
        "Fetching document '$documentId'..."
    $document = (az cleanroom governance document show `
        --id $documentId `
        --governance-client $cgsClient `
        --output json | ConvertFrom-Json)

    if ($contractId -eq $document.contractId)
    {
        Write-Log Verbose `
            "Document '$documentId' for contract '$contractId' is in state '$($document.state)':"
        Write-Log Information `
            "$($document.data)"
        az cleanroom governance document vote `
            --id $documentId `
            --proposal-id $document.proposalId `
            --action accept `
            --governance-client $cgsClient

        Write-Log OperationCompleted `
            "Accepted document '$documentId' for contract '$contractId'."
    }
    else
    {
        Write-Log Verbose `
            "Skipped '$documentId' for contract '$($document.contractId)'."
    }
}