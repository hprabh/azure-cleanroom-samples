param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("litware", "fabrikam", "contosso", "client", "operator")]
    [string]$memberName,
    [string]$resourceGroup = "",
    [string]$imageName = "azure-cleanroom-samples",
    [switch]$customCliExtension
)

# (TODO) Cut across to prebuild docker image once we setup the repository.
$localImage = (docker image ls $imageName --format 'json') | ConvertFrom-Json
if ($null -eq $localImage.ID) { 
    $dockerArgs = "image build -t $imageName -f ./docker/Dockerfile.multi-party-collab `".`""

    if ($customCliExtension)
    {
        $dockerArgs += " --build-arg EXTENSION_SOURCE=local"
    }

    Write-Host "docker $dockerArgs"
    Start-Process docker $dockerArgs
}

if ($resourceGroup -eq "")
{
    $resourceGroup = "$memberName-$((New-Guid).ToString().Substring(0, 8))"
}

docker create `
    --env MEMBER_NAME=$memberName `
    --env RESOURCE_GROUP=$resourceGroup `
    -v "//var/run/docker.sock:/var/run/docker.sock" `
    -v "$pwd/demo-resources/resources.public:/home/samples/demo-resources.public" `
    -v "$pwd/demo-resources/resources.$memberName.private:/home/samples/demo-resources.private" `
    -v "$pwd/demo-resources/resources.$memberName.secret:/home/samples/demo-resources.secret" `
    --name "$memberName-shell" `
    -it $imageName

docker container start -a -i "$memberName-shell"
