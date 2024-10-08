param(
    [string]$persona = "$env:PERSONA",

    [string]$samplesRoot = "/home/samples",
    [string]$secretDir = "$samplesRoot/demo-resources.secret",
    [string]$publicDir = "$samplesRoot/demo-resources.public",

    [string]$ccfEndpoint = (Get-Content "$publicDir/ccfEndpoint"),
    [string]$cgsClient = "$persona-client"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Write-Host "$($PSStyle.Dim)" `
    "Joining consortium '$ccfEndpoint'..."

# Deploy client-side containers to interact with the governance service as the new member.
az cleanroom governance client deploy `
    --ccf-endpoint $ccfEndpoint `
    --signing-cert $secretDir/$($persona)_cert.pem `
    --signing-key $secretDir/$($persona)_privk.pem `
    --name $cgsClient

# Accept the invitation and becomes an active member in the consortium.
az cleanroom governance member activate --governance-client $cgsClient

Write-Host "$($PSStyle.Formatting.Warning)" `
    "Joined consortium '$ccfEndpoint' and deployed CGS client '$cgsClient'."
