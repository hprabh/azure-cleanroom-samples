param(
    [string]$image = "cleanroomsamples.azurecr.io/azure-cleanroom-samples/demos/analytics@sha256:303f94478f7908c94958d1c3651a754f493e54cac23e39b9b2b096d7e8931387",
    [string]$endpointPolicy = "",

    [ValidateSet("litware")]
    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",

    [string]$demo = "$(Split-Path $PSScriptRoot -Leaf)",
    [string]$contractConfig = "$privateDir/$resourceGroup-$demo.generated.json"
)

if (-not (("litware") -contains $persona))
{
    Write-Host -ForegroundColor Yellow `
        "No action required for persona '$persona' in demo '$demo'."
    return
}

$configResult = Get-Content $contractConfig | ConvertFrom-Json
Write-Host -ForegroundColor DarkGray `
    "Adding application details for '$persona' in the '$demo' demo to " `
    "'$($configResult.contractFragment)'..."

az cleanroom config add-application `
    --cleanroom-config $configResult.contractFragment `
    --name demoapp-$demo `
    --image $image `
    --command "python3.10 ./analytics.py" `
    --mounts "src=fabrikam-input,dst=/mnt/remote/fabrikam-input" `
             "src=contosso-input,dst=/mnt/remote/contosso-input" `
    --env-vars STORAGE_PATH_1=/mnt/remote/fabrikam-input `
               STORAGE_PATH_2=/mnt/remote/contosso-input `
    --cpu 0.5 `
    --memory 4

az cleanroom config add-application-endpoint `
    --cleanroom-config $configResult.contractFragment `
    --application-name demoapp-$demo `
    --port 8310

Write-Host -ForegroundColor Yellow `
    "Added application 'demoapp-$demo' ($image)."