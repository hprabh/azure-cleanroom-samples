param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$demo,

    [string[]]$collaborators = ('litware', 'fabrikam', 'contosso'),

    [string]$cgsClient = "$env:PERSONA-client",

    [string]$samplesRoot = "/home/samples",
    [string]$publicDir = "$samplesRoot/demo-resources.public",

    [string]$contractId = "collab-$demo-$((New-Guid).ToString().Substring(0, 8))",
    [string]$cleanroomConfig = "$publicDir/$contractId-cleanroom.config"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Write-Host -ForegroundColor Gray `
    "Generating cleanroom specification for contract '$contractId' at '$cleanroomConfig'..." 
az cleanroom config init `
    --cleanroom-config $cleanroomConfig

# Generate the cleanroom config which contains all the datasources, sinks and applications that are
# configured by the collaborators.
$azArgs = "cleanroom config view --cleanroom-config $cleanroomConfig --output-file $cleanroomConfig --configs "
foreach ($collaboratorName in $collaborators)
{
    $fragment = "./$publicDir/$collaboratorName-$demo.config"
    Write-Host -ForegroundColor Gray `
        "Adding fragment for '$collaboratorName' ('$fragment')..."
    $azArgs = $azArgs + "$fragment "
}

Start-Process az $azArgs -Wait
Write-Host -ForegroundColor Yellow `
    "Generated cleanroom specification for contract '$contractId' at '$cleanroomConfig'." 

# Validate the contract structure before proposing.
az cleanroom config validate --cleanroom-config $cleanroomConfig

Write-Host -ForegroundColor Gray `
    "Proposing contract '$contractId' to the consortium..." 

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

Write-Host -ForegroundColor Gray `
    "Proposed contract for '$contractId' to the consortium." 