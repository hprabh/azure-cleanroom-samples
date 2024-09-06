param(
    [string]$memberName = "$env:MEMBER_NAME",
    [string]$collaborators = ('litware', 'fabrikam', 'contosso'),
    [string]$publicFolder = "./demo-resources.public"
)

foreach ($collaboratorName in $collaborators)
{
    # Makes a proposal for adding the new member.
    $proposalId = (az cleanroom governance member add `
        --certificate $publicFolder/$($collaboratorName)_cert.pem `
        --identifier $collaboratorName `
        --tenant-id (Get-Content "$publicFolder/$collaboratorName.tenantid") `
        --query "proposalId" `
        --output tsv `
        --governance-client "$memberName-client")

    # Vote on the above proposal to accept the membership.
    az cleanroom governance proposal vote `
        --proposal-id $proposalId `
        --action accept `
        --governance-client "$memberName-client"
}