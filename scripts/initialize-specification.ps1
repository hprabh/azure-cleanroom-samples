param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("analytics")]
    [string]$scenario,

    [string]$resourceConfig = "./demo-resources.private/$env:RESOURCE_GROUP.generated.json",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",
    [string]$outDir = "./demo-resources.private"
)

. $outDir/names.generated.ps1

$initResult = Get-Content $resourceConfig | ConvertFrom-Json

$cleanroom_config_file = "$outDir/$resourceGroup-$scenario.config"
az cleanroom config init `
    --cleanroom-config $cleanroom_config_file

az cleanroom config set-kek `
    --kek-key-vault $initResult.kek.kv.id `
    --maa-url $initResult.maa_endpoint `
    --cleanroom-config $cleanroom_config_file

$managedIdentityName = "$MANAGED_IDENTITY_NAME_PREFIX-$scenario"
$resourceGroup = $RESOURCE_GROUP
Write-Host "Creating managed identity $managedIdentityName in resource group $resourceGroup"
$managedIdentityResult = (az identity create `
        --name $managedIdentityName `
        --resource-group $resourceGroup) | ConvertFrom-Json

$configResult = @{
    configFile = ""
    mi         = @{}
}

$configResult.configFile = $cleanroom_config_file
$configResult.mi = $managedIdentityResult

$configResult | ConvertTo-Json -Depth 100 > "$outDir/$resourceGroup-$scenario.generated.json"

return $configResult