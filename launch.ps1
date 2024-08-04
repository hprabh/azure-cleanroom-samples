param(
    [Parameter(Mandatory = $true)]
    [string]$customerName,

    [string]$imageName = "samples.take01"
)

$resourceGroup = "$customerName-$((New-Guid).ToString().Substring(0, 8))"

docker create `
    --env CUSTOMERNAME=$customerName `
    --env RESOURCEGROUP=$resourceGroup `
    -v "//var/run/docker.sock:/var/run/docker.sock" `
    -v "$pwd/demo-resources/$customerName.public:/home/samples/demo-resources.public" `
    -v "$pwd/demo-resources/$customerName.private:/home/samples/demo-resources.private" `
    --name "$customerName-shell" `
    -it $imageName

docker container start -a -i "$customerName-shell"
