param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$demo,

    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",

    [string]$datastoreDir = "$privateDir/datastores",
    [string]$contractConfig = "$privateDir/$resourceGroup-$demo.generated.json",
    [string]$datastoreConfig = "$privateDir/datastores.config"
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
    $telemetryFolder = "$datastoreDir/infrastructure-telemetry/$demo"
    mkdir -p $telemetryFolder

    az cleanroom telemetry download `
        --cleanroom-config $contractConfigResult.contractFragment `
        --datastore-config $datastoreConfig `
        --target-folder $telemetryFolder
    # TODO (phanic): Fetch exact name of the backing datastore from the clean room spec.
    $dataDir = "$telemetryFolder/infrastructure-telemetry-*"
    Write-Log OperationCompleted `
        "Downloaded infrastructure telemetry to '$dataDir'."

    $logsFolder = "$datastoreDir/application-telemetry/$demo"
    mkdir -p $logsFolder

    az cleanroom logs download `
        --cleanroom-config $contractConfigResult.contractFragment `
        --datastore-config $datastoreConfig `
        --target-folder $logsFolder
    # TODO (phanic): Fetch exact name of the backing datastore from the clean room spec.
    $dataDir = "$logsFolder/application-telemetry-*"
    Write-Log OperationCompleted `
        "Downloaded application telemetry to '$dataDir'."

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