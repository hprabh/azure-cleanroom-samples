param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$demo,

    [Parameter(Mandatory = $true)]
    [string]$contractId,

    [string]$persona = "$env:PERSONA",

    [string]$samplesRoot = "/home/samples",
    [string]$demosRoot = "$samplesRoot/demos",
    [string]$documentPath = "$demosRoot/$demo/document/$persona",
    [string]$cgsClient = "$persona-client"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

Write-Log OperationStarted `
    "Proposing documents for '$demo' demo..."

if (Test-Path -Path $documentPath)
{
    Write-Log Verbose `
        "Enumerating documents in '$documentPath'..."

    $documents = Get-ChildItem -Path $documentPath -File
    foreach ($document in $documents)
    {
        $data = Get-Content $document
        $documentId = "$demo-$persona-$($document.Name)-$contractId".ToLower()

        az cleanroom governance document create `
            --data $data `
            --id $documentId `
            --contract-id $contractId `
            --governance-client $cgsClient
    
        $version = az cleanroom governance document show `
            --id $documentId `
            --governance-client $cgsClient `
        | jq -r ".version"
    
        # Submitting a document proposal.
        $proposalId = az cleanroom governance document propose `
            --version $version `
            --id $documentId `
            --governance-client $cgsClient `
        | jq -r '.proposalId'

        Write-Log OperationCompleted `
            "Proposed document '$documentId' to consortium ('$proposalId')."
    }
}
else
{
    Write-Log Warning `
        "No document available for persona '$persona' in demo '$demo'."
}
