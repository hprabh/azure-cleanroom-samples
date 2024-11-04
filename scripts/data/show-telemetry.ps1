param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$demo,

    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",
    [string]$telemetryDir = "$privateDir/demo-resources.telemetry",

    [string]$contractConfig = "$privateDir/$resourceGroup-$demo.generated.json",
    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$dashboardName = "azure-cleanroom-samples-telemetry"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../common/common.psm1

$contractConfigResult = Get-Content $contractConfig | ConvertFrom-Json

# TODO (phanic): Add check to see if member had configured telemetry.
$telemetryConfigured = $true

if ($telemetryConfigured)
{
    #
    # Download infrastructure telemetry.
    #
    $infrastructureDir = "$telemetryDir/infrastructure-telemetry/$demo"
    mkdir -p $infrastructureDir
    az cleanroom telemetry download `
        --cleanroom-config $contractConfigResult.contractFragment `
        --datastore-config $datastoreConfig `
        --target-folder $infrastructureDir
    # TODO (phanic): Fetch exact name of the backing datastore from the clean room spec.
    $dataDir = "$infrastructureDir/infrastructure-telemetry-*"
    Write-Log OperationCompleted `
        "Downloaded infrastructure telemetry to '$dataDir'."

    # Display dashboard details.
    $dashboardUrl = docker compose -p $dashboardName port "aspire" 18888
    $dashboardPort = ($dashboardUrl -split ":")[1]
    Write-Log OperationCompleted `
        "Open Aspire dashboard at http://localhost:$dashboardPort to view" `
        "infrastructure telemetry."

    #
    # Download application telemetry.
    #
    $applicationDir = "$telemetryDir/application-telemetry/$demo"
    mkdir -p $applicationDir
    az cleanroom logs download `
        --cleanroom-config $contractConfigResult.contractFragment `
        --datastore-config $datastoreConfig `
        --target-folder $applicationDir
    # TODO (phanic): Fetch exact name of the backing datastore from the clean room spec.
    $dataDir = "$applicationDir/application-telemetry-*"
    Write-Log OperationCompleted `
        "Downloaded application telemetry to '$dataDir'."

    # Display application logs.
    Write-Log Verbose `
        "-----BEGIN OUTPUT-----" `
        "$($PSStyle.Reset)"
    cat "$dataDir/**/demoapp-$demo.log"
    Write-Log Verbose `
        "$([environment]::NewLine)-----END OUTPUT-----"
}
else
{
    Write-Log Warning `
        "No telemetry available for persona '$persona' in demo '$demo'."
}