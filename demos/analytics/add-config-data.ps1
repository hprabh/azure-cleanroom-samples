param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("fabrikam", "contosso")]
    [string]$persona,
    [string]$cleanroom_config_file,
    [string]$datastore_config_file,
    [string]$keystore,
    [string]$identity
)
$datastoreName = "analytics-$persona-input"
$datasourceName = "$persona-input"

az cleanroom config add-datasource-v2 `
    --cleanroom-config-file $cleanroom_config_file `
    --name $datasourceName `
    --datastore-config $datastore_config_file `
    --datastore-name $datastoreName `
    --key-vault $keystore `
    --identity $identity
