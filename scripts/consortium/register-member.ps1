param(
    [string[]]$collaborators = ('litware', 'fabrikam', 'contosso'),

    [string]$cgsClient = "$env:MEMBER_NAME-client",

    [string]$publicDir = "./demo-resources.public"
)

foreach ($collaboratorName in $collaborators)
{
    Write-Host "Registering member '$collaboratorName'"

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
}