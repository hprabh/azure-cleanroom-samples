param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("litware", "fabrikam", "contosso", "client", "operator")]
    [string]$persona,

    [string]$resourceGroup = "",
    [string]$resourceGroupLocation = "westus",

    [string]$imageName = "azure-cleanroom-samples",
    [string]$dockerFileDir = "./docker",

    [string]$dashboardName = "$imageName-telemetry",

    [switch]$overwrite
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

#
# Launch telemetry dashboard.
#
docker build -f $dockerFileDir/Dockerfile.azure-cleanroom-samples-otelcollector -t $imageName-otelcollector $dockerFileDir

$telemetryPath = "$pwd/demo-resources/resources.telemetry"
mkdir -p $telemetryPath
$env:TELEMETRY_FOLDER = $telemetryPath
$dashboardName = "$imageName-telemetry"
docker compose -p $dashboardName -f $dockerFileDir/telemetry/docker-compose.yaml up -d --remove-orphans
$dashboardUrl = docker compose -p $dashboardName port "aspire" 18888
$dashboardPort = ($dashboardUrl -split ":")[1]
Write-Log OperationCompleted `
    "Aspire dashboard deployed at http://localhost:$dashboardPort."

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
    docker create `
        --env PERSONA=$persona `
        --env RESOURCE_GROUP=$resourceGroup `
        --env RESOURCE_GROUP_LOCATION=$resourceGroupLocation `
        -v "//var/run/docker.sock:/var/run/docker.sock" `
        -v "$pwd/demo-resources/resources.public:/home/samples/demo-resources.public" `
        -v "$pwd/demo-resources/resources.telemetry:/home/samples/demo-resources.telemetry" `
        -v "$pwd/demo-resources/resources.$persona.private:/home/samples/demo-resources.private" `
        -v "$pwd/demo-resources/resources.$persona.secret:/home/samples/demo-resources.secret" `
        --network host `
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