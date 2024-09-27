param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("litware", "fabrikam", "contosso", "client", "operator")]
    [string]$persona,

    [string]$resourceGroup = "",
    [string]$resourceGroupLocation = "westus",

    [string]$imageName = "azure-cleanroom-samples",
    [string]$dockerFileDir = "./docker"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# TODO (phanic) Cut across to prebuilt docker image once we setup the repository.
$localImage = (docker image ls $imageName --format 'json') | ConvertFrom-Json
if ($null -eq $localImage.ID)
{ 
    Write-Host -ForegroundColor Yellow `
        "Building container image '$imageName' for starting the samples environment..." 

    $dockerArgs = "image build -t $imageName -f $dockerFileDir/Dockerfile.multi-party-collab `".`""

    $customCliExtensionPath = "$dockerFileDir/cleanroom-0.0.3-py2.py3-none-any.whl"
    if (Test-Path -Path $customCliExtensionPath)
    {
        Write-Host -ForegroundColor Yellow `
            "Using custom az cli extensions from '$customCliExtensionPath'..."
        $dockerArgs += " --build-arg EXTENSION_SOURCE=local"
    }

    Start-Process docker $dockerArgs -Wait
}
else
{
    Write-Host -ForegroundColor Yellow `
        "Using local container image '$imageName' for starting the samples environment..."
}

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
    -v "$pwd/demo-resources/resources.$persona.private:/home/samples/demo-resources.private" `
    -v "$pwd/demo-resources/resources.$persona.secret:/home/samples/demo-resources.secret" `
    --network host `
    --name "$persona-shell" `
    -it $imageName
Write-Host -ForegroundColor Yellow `
    "Created container image '$persona-shell' to start samples environment for " `
    "'$persona'. Environment will be using resource group '$resourceGroup'."

Write-Host -ForegroundColor Gray `
    "Starting samples environment..."
docker container start -a -i "$persona-shell"
