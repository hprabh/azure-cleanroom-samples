param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("litware", "fabrikam", "contosso", "client", "operator")]
    [string]$persona,

    [string]$resourceGroup = "",
    [string]$resourceGroupLocation = "westus",

    [string]$imageName = "azure-cleanroom-samples",
    [string]$dockerFileDir = "./docker",

    [string]$accessTokenProviderName = "$imageName-credential-proxy",
    [string]$ccfProviderName = "$imageName-ccf-provider",
    [string]$telemetryDashboardName = "$imageName-telemetry",

    [switch]$overwrite,
    [switch]$shareCredentials
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

Import-Module $PSScriptRoot/scripts/common/common.psm1

function Get-Confirmation {
    param (
        [string]$Message = "Are you sure?",
        [string]$YesLabel = "Yes",
        [string]$NoLabel = "No"
    )

    do {
        $choice = Read-Host "$($PSStyle.Bold)$Message ('$YesLabel'/'$NoLabel')$($PSStyle.Reset)"
        $choice = $choice.ToLower()
        switch ($choice) {
            $YesLabel.ToLower() {
                $response = $choice
                break
            }
            $NoLabel.ToLower() {
                $response = $choice
                break
            }
            default {
                Write-Log Error `
                    "Invalid input. Please enter '$YesLabel' or '$NoLabel'."
            }
        }
    } while ($response -ne $YesLabel.ToLower() -and $response -ne $NoLabel.ToLower())

    return ($response -eq $YesLabel.ToLower())
}

$hostBase = "$pwd/demo-resources"
$sharedBase = "$hostBase/shared"
$personaBase = "$hostBase/$persona"
$virtualBase = "/home/samples/demo-resources"

#
# Create host directories shared by sample environment containers for all persona.
#
$publicDir = "$sharedBase/public"
mkdir -p $publicDir
$telemetryDir = "$sharedBase/telemetry"
mkdir -p $telemetryDir

#
# Create host directories private to sample environment containers per persona.
#
$privateDir = "private"
mkdir -p "$personaBase/$privateDir"
$secretDir = "secret"
mkdir -p "$personaBase/$secretDir"

$networkName = "$imageName-network"
$network = (docker network ls --filter "name=^$networkName$" --format 'json') | ConvertFrom-Json
if ($null -eq $network)
{
    docker network create $networkName
}

#
# Launch credential proxy if sharing credentials.
#
if ($shareCredentials -or ($persona -eq "operator"))
{
    $containerName = $accessTokenProviderName
    $container = (docker container ls -a --filter "name=^$containerName$" --format 'json') | ConvertFrom-Json
    if ($null -eq $container)
    {
        docker container create `
            -p "0:8080" `
            --network $networkName `
            --name $containerName `
            "workleap/azure-cli-credentials-proxy"
    }

    docker container start $containerName

    $PSNativeCommandUseErrorActionPreference = $false
    $(docker exec $containerName sh -c "az account get-access-token")
    $PSNativeCommandUseErrorActionPreference = $true

    if (0 -ne $LASTEXITCODE)
    {
        docker exec -it $containerName sh -c "az login"
    }

    docker exec $containerName sh -c "az account show"
    $credentialProxyEndpoint = "http://$($accessTokenProviderName):8080/token"
}

#
# Launch telemetry dashboard for 'litware'.
#
if ($persona -eq "litware")
{
    docker build -f $dockerFileDir/Dockerfile.azure-cleanroom-samples-otelcollector -t $imageName-otelcollector $dockerFileDir

    $env:TELEMETRY_FOLDER = $telemetryDir
    $dashboardName = "$imageName-telemetry"
    docker compose -p $dashboardName -f $dockerFileDir/telemetry/docker-compose.yaml up -d --remove-orphans

    $dashboardUrl = docker compose -p $dashboardName port "aspire" 18888
    $dashboardPort = ($dashboardUrl -split ":")[1]
    Write-Log OperationCompleted `
        "Aspire dashboard deployed at http://localhost:$dashboardPort."
}

#
# Launch CCF provider for 'operator' and share az cli configuration directory.
#
if ($persona -eq "operator")
{
    # $containerName = $ccfProviderName
    # $container = (docker container ls -a --filter "name=^$containerName$" --format 'json') | ConvertFrom-Json
    # if ($null -eq $container)
    # {
    #     docker container create `
    #         --env IDENTITY_ENDPOINT="http://$($accessTokenProviderName):8080/token" `
    #         --env IMDS_ENDPOINT="dummy_required_value" `
    #         -v "//var/run/docker.sock:/var/run/docker.sock" `
    #         -p "0:8080" `
    #         --network $networkName `
    #         --name $containerName `
    #         "mcr.microsoft.com/cleanroom/ccf/ccf-provider-client:1.0.11"
    # }

    # docker container start $containerName

    $env:NETWORK_NAME = $networkName
    $env:CREDENTIAL_PROXY_ENDPOINT = $credentialProxyEndpoint
    docker compose -p $ccfProviderName -f $dockerFileDir/ccf/docker-compose.yaml up -d --remove-orphans
}

#
# Launch sample environment.
#
$containerName = "$persona-shell"
$container = (docker container ls -a --filter "name=^$containerName$" --format 'json') | ConvertFrom-Json
if ($null -eq $container)
{
    $createContainer = $true
}
else
{
    Write-Log Warning `
        "Samples environment for '$persona' already exists - '$($container.Names)' (ID: $($container.ID))."
    $overwrite = $overwrite -or 
        (Get-Confirmation -Message "Overwrite container '$containerName'?" -YesLabel "Y" -NoLabel "N")
    if ($overwrite)
    {
        Write-Log Warning `
            "Deleting container '$containerName'..."
        docker container rm -f $containerName
        $createContainer = $true
    }
    else
    {
        $createContainer = $false
    }
}

if ($createContainer)
{
    Write-Log OperationStarted `
        "Creating samples environment '$containerName' using image '$imageName'..." 

    # TODO (phanic) Cut across to prebuilt docker image once we setup the repository.
    $dockerArgs = "image build -t $imageName -f $dockerFileDir/Dockerfile.azure-cleanroom-samples `".`""
    $customCliExtensions = @(Get-Item -Path "./docker/*.whl")
    if (0 -ne $customCliExtensions.Count)
    {
        Write-Log Warning `
            "Using custom az cli extensions: $customCliExtensions..."
        $dockerArgs += " --build-arg EXTENSION_SOURCE=local"
    }
    Start-Process docker $dockerArgs -Wait

    if ($resourceGroup -eq "")
    {
        $resourceGroup = "$persona-$((New-Guid).ToString().Substring(0, 8))"
    }

    docker container create `
        --env PERSONA=$persona `
        --env RESOURCE_GROUP=$resourceGroup `
        --env RESOURCE_GROUP_LOCATION=$resourceGroupLocation `
        --env MSI_ENDPOINT="http://$($accessTokenProviderName):8080/token" `
        -v "//var/run/docker.sock:/var/run/docker.sock" `
        -v "$($sharedBase):$virtualBase" `
        -v "$personaBase/$($privateDir):$virtualBase/$privateDir" `
        -v "$personaBase/$($secretDir):$virtualBase/$secretDir" `
        --network $networkName `
        --name $containerName `
        -it $imageName
    Write-Log OperationCompleted `
        "Created container '$containerName' to start samples environment for" `
        "'$persona'. Environment will be using resource group '$resourceGroup'."
}

Write-Log OperationStarted `
    "Starting samples environment using container '$containerName'..."
docker container start -a -i $containerName

Write-Log Warning `
    "Samples environment exited!"