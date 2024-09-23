param(
    [string]$image = "cleanroomsamples.azurecr.io/azure-cleanroom-samples/demos/analytics@sha256:303f94478f7908c94958d1c3651a754f493e54cac23e39b9b2b096d7e8931387",
    [string]$endpointPolicy = "",

    [ValidateSet("litware")]
    [string]$persona = "$env:MEMBER_NAME",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$privateDir = "./demo-resources.private",

    [string]$scenario = "$(Split-Path $PSScriptRoot -Leaf)",
    [string]$cleanroomConfig = "$privateDir/$resourceGroup-$scenario.generated.json"
)

if (-not (("litware") -contains $persona))
{
    Write-Host "No action required for persona '$persona' in this scenario."
    return
}

$cleanroomConfigResult = Get-Content $cleanroomConfig | ConvertFrom-Json

az cleanroom config add-application `
    --cleanroom-config $cleanroomConfigResult.configFile `
    --name demoapp-$scenario `
    --image $image `
    --command "python3.10 ./analytics.py" `
    --mounts "src=fabrikam-input,dst=/mnt/remote/fabrikam-input" `
             "src=contosso-input,dst=/mnt/remote/contosso-input" `
    --env-vars STORAGE_PATH_1=/mnt/remote/fabrikam-input `
               STORAGE_PATH_2=/mnt/remote/contosso-input `
    --cpu 0.5 `
    --memory 4

az cleanroom config add-application-endpoint `
    --cleanroom-config $cleanroomConfigResult.configFile `
    --application-name demoapp-$scenario `
    --port 8310
