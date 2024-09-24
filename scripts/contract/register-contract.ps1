param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$scenario,

    [string[]]$collaborators = ('litware', 'fabrikam', 'contosso'),

    [string]$cgsClient = "$env:MEMBER_NAME-client",

    [string]$publicDir = "./demo-resources.public",

    [string]$cleanroomConfig = "$publicDir/finalized-$scenario.config",
    [string]$contractId = "collab-$scenario" # A unique identifier to refer to this collaboration.
)

az cleanroom config init `
    --cleanroom-config $cleanroomConfig

# Generate the cleanroom config which contains all the datasources, sinks and applications that are
# configured by the collaborators.
$azArgs = "cleanroom config view --cleanroom-config $cleanroomConfig --output-file $cleanroomConfig --configs "
foreach ($collaboratorName in $collaborators)
{
    Write-Host "Adding fragment for member '$collaboratorName'"
    $azArgs = $azArgs + "./$publicDir/$collaboratorName-$scenario.config "
}

Start-Process az $azArgs -Wait


# Validate the contract structure before proposing.
az cleanroom config validate --cleanroom-config $cleanroomConfig

$data = Get-Content -Raw $cleanroomConfig
az cleanroom governance contract create `
    --data "$data" `
    --id $contractId `
    --governance-client $cgsClient

# Submitting a contract proposal.
$version = (az cleanroom governance contract show `
    --id $contractId `
    --query "version" `
    --output tsv `
    --governance-client $cgsClient)

az cleanroom governance contract propose `
    --version $version `
    --id $contractId `
    --query "proposalId" `
    --output tsv `
    --governance-client $cgsClient
