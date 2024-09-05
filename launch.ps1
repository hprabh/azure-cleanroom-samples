param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("litware", "fabrikam", "contosso", "client", "operator")]
    [string]$memberName,

    [string]$imageName = "azure-cleanroom-samples"
)

$resourceGroup = "$memberName-$((New-Guid).ToString().Substring(0, 8))"

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
