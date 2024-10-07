param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("litware", "fabrikam", "contosso", "client", "operator")]
    [string]$persona,

    [string]$resourceGroup = "",
    [string]$resourceGroupLocation = "westus",

    [string]$imageName = "azure-cleanroom-samples",
    [string]$dockerFileDir = "./docker",
    [switch]$overwrite
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Get-Confirmation {
    param (
        [string]$Message = "Are you sure?",
        [string]$YesLabel = "Yes",
        [string]$NoLabel = "No"
    )

    do {
        $choice = Read-Host `
            "$Message ($YesLabel/$NoLabel)"
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
                Write-Host "Invalid input. Please enter '$YesLabel' or '$NoLabel'."
            }
        }
    } while ($response -ne $YesLabel.ToLower() -and $response -ne $NoLabel.ToLower())

    return ($response -eq $YesLabel.ToLower())
}

$containerName = "$persona-shell"
$container = (docker container ls -a --filter "name=^$containerName$" --format 'json') | ConvertFrom-Json
if ($null -eq $container)
{
    $createContainer = $true
}
else
{
    # TODO (phanic): Scrub all Write-Host to have right colours and background.
    Write-Host -ForegroundColor Yellow `
        "Samples environment for '$persona' already exists - $($container.Names) ($($container.ID))."
    $overwrite = $overwrite -or
        (Get-Confirmation -Message "Overwrite container '$containerName'?" -YesLabel "Y" -NoLabel "N")
    if ($overwrite)
    {
        Write-Host -ForegroundColor Yellow `
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
    Write-Host -ForegroundColor Yellow `
        "Creating samples environment '$containerName' using image '$imageName'..." 

    # TODO (phanic) Cut across to prebuilt docker image once we setup the repository.
    $dockerArgs = "image build -t $imageName -f $dockerFileDir/Dockerfile.multi-party-collab `".`""
    $customCliExtensions = @(Get-Item -Path "./docker/*.whl")
    if (0 -ne $customCliExtensions.Count)
    {
        Write-Host -ForegroundColor Yellow `
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
        -v "$pwd/demo-resources/resources.$persona.private:/home/samples/demo-resources.private" `
        -v "$pwd/demo-resources/resources.$persona.secret:/home/samples/demo-resources.secret" `
        --network host `
        --name $containerName `
        -it $imageName
    Write-Host -ForegroundColor Yellow `
        "Created container '$containerName' to start samples environment for " `
        "'$persona'. Environment will be using resource group '$resourceGroup'."
}

Write-Host -ForegroundColor DarkGray `
    "Starting samples environment..."
docker container start -a -i $containerName
