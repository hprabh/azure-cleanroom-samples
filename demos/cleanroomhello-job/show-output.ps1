param(
    [string]$persona = "$env:PERSONA",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",

    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datastoreDir = "$privateDir/datastores",
    [string]$demo = "$(Split-Path $PSScriptRoot -Leaf)",
    [string]$datasinkPath = "$PSScriptRoot/datasink/$persona"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/../../scripts/common/common.psm1

if (Test-Path -Path $datasinkPath)
{
    $dirs = Get-ChildItem -Path $datasinkPath -Directory -Name
    foreach ($dir in $dirs)
    {
        $datasinkName = "$persona-$dir".ToLower()
        Write-Log Verbose `
            "Enumerated datasink '$datasinkName' in '$datasinkPath'..."

        $datastoreName = "$demo-$persona-$dir".ToLower()
        # TODO (phanic): Understand why this is being copied into a nested folder.
        $datastoreFolder = "$datastoreDir/$datastoreName/**"
        Write-Log Information `
            "Output from datastore '$datastoreName':"
        Write-Log Verbose `
            "-----BEGIN OUTPUT-----" `
            "$($PSStyle.Reset)"
        gzip -c -d $datastoreFolder/*.gz
        Write-Log Verbose `
            "-----END OUTPUT-----"
    }
}
else
{
    Write-Log Warning `
        "No output available for persona '$persona' in demo '$demo'."
}
