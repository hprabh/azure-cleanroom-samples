param(
    [string]$persona = "$env:PERSONA",

    [string[]]$collaborators = ('litware', 'fabrikam', 'contosso'),

    [string]$samplesRoot = "/home/samples",
    [string]$publicDir = "$samplesRoot/demo-resources.public",

    [string]$cgsClient = "$persona-client"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Write-Host -ForegroundColor Gray `
    "Adding '$collaborators' to the consortium..." 

foreach ($collaboratorName in $collaborators)
{
    # Makes a proposal for adding the new member.
    $proposalId = (az cleanroom governance member add `
        --certificate $publicDir/$($collaboratorName)_cert.pem `
        --identifier $collaboratorName `
        --tenant-id (Get-Content "$publicDir/$collaboratorName.tenantid") `
        --query "proposalId" `
        --output tsv `
        --governance-client $cgsClient)

    # Vote on the above proposal to accept the membership.
    az cleanroom governance proposal vote `
        --proposal-id $proposalId `
        --action accept `
        --governance-client $cgsClient

    Write-Host -ForegroundColor Yellow `
        "Added '$collaboratorName' to the consortium."
}