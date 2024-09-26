param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$scenario,

    [string]$persona = "$env:MEMBER_NAME",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$privateDir = "./demo-resources.private",
    [string]$secretDir = "./demo-resources.secret",

    [string]$datastoreDir = "$privateDir/datastores",
    [string]$cleanroomConfig = "$privateDir/$resourceGroup-$scenario.generated.json",
    [string]$datastoreConfig = "$privateDir/datastores.config"
)

$cleanroomConfigResult = Get-Content $cleanroomConfig | ConvertFrom-Json

# TODO (phanic): Add check to see if member had configured telemetry.
if ($true)
{
    az cleanroom telemetry download `
        --cleanroom-config $cleanroomConfigResult.configFile `
        --datastore-config $datastoreConfig `
        --target-folder $datastoreDir

    az cleanroom logs download `
        --cleanroom-config $cleanroomConfigResult.configFile `
        --datastore-config $datastoreConfig `
        --target-folder $datastoreDir
}
else
{
    Write-Host "No telemetry download available for persona '$persona' in scenario '$scenario'."
}

