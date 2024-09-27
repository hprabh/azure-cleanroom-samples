param(
    [string]$image = "docker.io/nginxdemos/nginx-hello:plain-text@sha256:d976f016b32fc381dfb74119cc421d42787b5a63a6b661ab57891b7caa5ad12e",
    [string]$endpointPolicy = "cleanroomsamples.azurecr.io/nginx-hello/nginx-hello-policy@sha256:c71b70a70dfad8279d063ab68d80df6d8d407ba8359a68c6edb3e99a25c77575",

    [ValidateSet("litware")]
    [string]$persona = "$env:PERSONA",
    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$samplesRoot = "/home/samples",
    [string]$privateDir = "$samplesRoot/demo-resources.private",

    [string]$scenario = "$(Split-Path $PSScriptRoot -Leaf)",
    [string]$contractConfig = "$privateDir/$resourceGroup-$scenario.generated.json"
)

if (-not (("litware") -contains $persona))
{
    Write-Host -ForegroundColor Yellow `
        "No action required for persona '$persona' in scenario '$scenario'."
    return
}

$configResult = Get-Content $contractConfig | ConvertFrom-Json
Write-Host -ForegroundColor Gray `
    "Adding application details for '$persona' in the '$scenario' scenario to " `
    "'$($configResult.contractFragment)'..."

az cleanroom config add-application `
    --cleanroom-config $configResult.contractFragment `
    --name demoapp-$scenario `
    --image $image `
    --cpu 0.5 `
    --memory 4

az cleanroom config add-application-endpoint `
    --cleanroom-config $configResult.contractFragment `
    --application-name demoapp-$scenario `
    --port 8080 `
    --policy $endpointPolicy

Write-Host -ForegroundColor Yellow `
    "Added application 'demoapp-$scenario' ($image)."