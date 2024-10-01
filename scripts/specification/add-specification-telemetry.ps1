param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$demo,

    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",
    [string]$secretDir = "$samplesRoot/demo-resources.secret",

    [string]$contractConfig = "$privateDir/$resourceGroup-$demo.generated.json",
    [string]$environmentConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$keysDir = "$secretDir/keys"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$contractConfigResult = Get-Content $contractConfig | ConvertFrom-Json
$environmentConfigResult = Get-Content $environmentConfig | ConvertFrom-Json

Write-Host -ForegroundColor Gray `
    "Adding telemetry details for '$persona' in the '$demo' demo to " `
    "'$($configResult.contractFragment)'..."

# $result below refers to the output of the prepare-resources.ps1 that was run earlier.
az cleanroom config set-logging `
    --cleanroom-config $contractConfigResult.contractFragment `
    --datastore-config $datastoreConfig `
    --datastore-keystore $keysDir `
    --storage-account $environmentConfigResult.sa.id `
    --identity "$persona-identity" `
    --key-vault $environmentConfigResult.dek.kv.id `
    --encryption-mode CPK
Write-Host -ForegroundColor Yellow `
    "Added application telemetry details."

az cleanroom config set-telemetry `
    --cleanroom-config $contractConfigResult.contractFragment `
    --datastore-config $datastoreConfig `
    --datastore-keystore $keysDir `
    --storage-account $environmentConfigResult.sa.id `
    --identity "$persona-identity" `
    --key-vault $environmentConfigResult.dek.kv.id `
    --encryption-mode CPK
Write-Host -ForegroundColor Yellow `
    "Added infrastructure telemetry details."

