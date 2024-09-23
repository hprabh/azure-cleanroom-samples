param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("analytics")]
    [string]$scenario,

    [string]$persona = "$env:MEMBER_NAME",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$privateDir = "./demo-resources.private",
    [string]$secretDir = "./demo-resources.secret",
    [string]$demosDir = "./demos",
    [string]$sa = "",

    [string]$resourceConfig = "$privateDir/$resourceGroup.generated.json",
    [string]$keyStore = "$secretDir/keys",
    [string]$datastoreConfig = "$privateDir/datastores.config",
    [string]$datastoreDir = "$privateDir/datastores",
    [string]$datasourcePath = "$demosDir/$scenario/datasource/$persona",
    [string]$datasinkPath = "$demosDir/$scenario/datasink/$persona"
)

if ($sa -eq "")
{
    $initResult = Get-Content $resourceConfig | ConvertFrom-Json
    $sa = $initResult.sa.id
}

if (Test-Path -Path $datasourcePath)
{
    $dirs = Get-ChildItem -Path $datasourcePath -Directory -Name
    foreach ($dir in $dirs)
    {
        $datastoreName = "$scenario-$persona-$dir".ToLower()

        Write-Host "Found datastore $datastoreName in $datasourcePath"
        az cleanroom datastore add `
            --name $datastoreName `
            --config $datastoreConfig `
            --keystore $keyStore `
            --encryption-mode CPK `
            --backingstore-type Azure_BlobStorage `
            --backingstore-id $sa

        $datastoreFolder = "$datastoreDir/$datastoreName"
        mkdir -p $datastoreFolder
        cp -r "$basePath/$dir" $datastoreFolder

        az cleanroom datastore upload `
            --name $datastoreName `
            --config $datastoreConfig `
            --src $datastoreFolder
    }
}
else
{
    Write-Host "No datastore found in $datasourcePath."
}


if (Test-Path -Path $datasinkPath)
{
    $dirs = Get-ChildItem -Path $datasinkPath -Directory -Name
    foreach ($dir in $dirs)
    {
        $datastoreName = "$scenario-$persona-$dir".ToLower()

        Write-Host "Found datastore $datastoreName in $datasinkPath"
        az cleanroom datastore add `
            --name $datastoreName `
            --config $datastoreConfig `
            --keystore $keyStore `
            --encryption-mode CPK `
            --backingstore-type Azure_BlobStorage `
            --backingstore-id $sa

        $datastoreFolder = "$datastoreDir/$datastoreName"
        mkdir -p $datastoreFolder
    }
}
else
{
    Write-Host "No datastore found in $datasinkPath."
}
