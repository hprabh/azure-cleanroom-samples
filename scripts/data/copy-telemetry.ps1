param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$scenario,

    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",
    [string]$secretDir = "$samplesRoot/demo-resources.secret",

    [string]$datastoreDir = "$privateDir/datastores",
    [string]$contractConfig = "$privateDir/$resourceGroup-$scenario.generated.json",
    [string]$datastoreConfig = "$privateDir/datastores.config"
)

$contractConfigResult = Get-Content $contractConfig | ConvertFrom-Json

# TODO (phanic): Add check to see if member had configured telemetry.
$telemetryConfigured = $true

if ($telemetryConfigured)
{
    az cleanroom telemetry download `
        --cleanroom-config $contractConfigResult.contractFragment `
        --datastore-config $datastoreConfig `
        --target-folder $datastoreDir
    # TODO (phanic): Fetch exact name of the backing datastore from the clean room spec.
    $dataDir = "$datastoreDir/infrastructure-telemetry-*"
    Write-Host -ForegroundColor Yellow `
        "Downloaded infrastructure telemetry to '$dataDir'."

    az cleanroom logs download `
        --cleanroom-config $contractConfigResult.contractFragment `
        --datastore-config $datastoreConfig `
        --target-folder $datastoreDir
    # TODO (phanic): Fetch exact name of the backing datastore from the clean room spec.
    $dataDir = "$datastoreDir/application-telemetry-*"
    Write-Host -ForegroundColor Yellow `
        "Downloaded application telemetry to '$dataDir'."
}
else
{
    Write-Host  -ForegroundColor Yellow
        "No telemetry download available for persona '$persona' in scenario '$scenario'."
}

