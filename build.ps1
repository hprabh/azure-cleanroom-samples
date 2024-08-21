param(
    [string]$imageName = "azure-cleanroom-samples",
    [switch]$customCliExtension
)

$dockerArgs = "image build -t $imageName -f ./docker/Dockerfile.multi-party-collab `".`""

if ($customCliExtension)
{
    $dockerArgs += " --build-arg EXTENSION_SOURCE=local"
}

Start-Process docker $dockerArgs