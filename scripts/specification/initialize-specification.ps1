param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("cleanroomhello-job", "cleanroomhello-api", "analytics")]
    [string]$scenario,

    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",
    [string]$publicDir = "$samplesRoot/demo-resources.public",

    [string]$environmentConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$contractConfig = "$privateDir/$resourceGroup-$scenario.generated.json",
    [string]$contractFragment = "$publicDir/$persona-$scenario.config",

    [string]$managedIdentityName = ""
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$initResult = Get-Content $environmentConfig | ConvertFrom-Json

Write-Host -ForegroundColor Gray `
    "Initializing cleanroom specification '$contractFragment'..." 
az cleanroom config init `
    --cleanroom-config $contractFragment
az cleanroom config set-kek `
    --kek-key-vault $initResult.kek.kv.id `
    --maa-url $initResult.maa_endpoint `
    --cleanroom-config $contractFragment

if ($managedIdentityName -eq "")
{
    $uniqueString = Get-UniqueString($resourceGroup)
    $managedIdentityName = "${uniqueString}-mi-$scenario"
}

Write-Host -ForegroundColor Gray `
    "Creating managed identity '$managedIdentityName' in resource group '$resourceGroup'..."
$mi = (az identity create `
    --name $managedIdentityName `
    --resource-group $resourceGroup) | ConvertFrom-Json
az cleanroom config add-identity az-federated `
    --cleanroom-config $contractFragment `
    -n "$persona-identity" `
    --client-id $mi.clientId `
    --tenant-id $mi.tenantId `
    --backing-identity cleanroom_cgs_oidc
Write-Host -ForegroundColor Yellow `
    "Added identity '$persona-identity' backed by '$managedIdentityName'."

$configResult = @{
    contractFragment = ""
    mi         = @{}
}
$configResult.contractFragment = $contractFragment
$configResult.mi = $mi

$configResult | ConvertTo-Json -Depth 100 | Out-File $contractConfig
Write-Host -ForegroundColor Yellow `
    "Contract configuration written to '$contractConfig'."
return $configResult