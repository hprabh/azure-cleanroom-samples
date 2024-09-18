param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("analytics")]
    [string]$scenario,

    [string]$persona = "$env:MEMBER_NAME",
    [string]$resourceConfig = "./demo-resources.private/$env:RESOURCE_GROUP.generated.json",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",
    [string]$cleanroomConfig = "./demo-resources.public/$env:MEMBER_NAME-$scenario.config",
    [string]$outDir = "./demo-resources.private"
)

. $outDir/names.generated.ps1

$initResult = Get-Content $resourceConfig | ConvertFrom-Json

az cleanroom config init `
    --cleanroom-config $cleanroomConfig

az cleanroom config set-kek `
    --kek-key-vault $initResult.kek.kv.id `
    --maa-url $initResult.maa_endpoint `
    --cleanroom-config $cleanroomConfig

$managedIdentityName = "$MANAGED_IDENTITY_NAME_PREFIX-$scenario"
$resourceGroup = $RESOURCE_GROUP
Write-Host "Creating managed identity $managedIdentityName in resource group $resourceGroup"
$managedIdentityResult = (az identity create `
        --name $managedIdentityName `
        --resource-group $resourceGroup) | ConvertFrom-Json

az cleanroom config add-identity az-federated `
    --cleanroom-config $cleanroomConfig `
    -n "$persona-identity" `
    --client-id $managedIdentityResult.clientId `
    --tenant-id $managedIdentityResult.tenantId `
    --backing-identity cleanroom_cgs_oidc

$configResult = @{
    configFile = ""
    mi         = @{}
}

$configResult.configFile = $cleanroomConfig
$configResult.mi = $managedIdentityResult

$configResult | ConvertTo-Json -Depth 100 > "$outDir/$resourceGroup-$scenario.generated.json"

return $configResult