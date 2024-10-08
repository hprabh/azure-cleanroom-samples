param(
    [string]$image = "docker.io/nginxdemos/nginx-hello:plain-text@sha256:d976f016b32fc381dfb74119cc421d42787b5a63a6b661ab57891b7caa5ad12e",
    [string]$endpointPolicy = "cleanroomsamples.azurecr.io/nginx-hello/nginx-hello-policy@sha256:c71b70a70dfad8279d063ab68d80df6d8d407ba8359a68c6edb3e99a25c77575",

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
    Write-Host "$($PSStyle.Formatting.ErrorAccent)" `
        "No action required for persona '$persona' in demo '$demo'."
    return
}

$configResult = Get-Content $contractConfig | ConvertFrom-Json
Write-Host "$($PSStyle.Formatting.CustomTableHeaderLabel)" `
    "Adding application details for '$persona' in the '$demo' demo to " `
    "'$($configResult.contractFragment)'..."

az cleanroom config add-application `
    --cleanroom-config $configResult.contractFragment `
    --name demoapp-$demo `
    --image $image `
    --cpu 0.5 `
    --memory 4

az cleanroom config add-application-endpoint `
    --cleanroom-config $configResult.contractFragment `
    --application-name demoapp-$demo `
    --port 8080 `
    --policy $endpointPolicy

Write-Host "$($PSStyle.Formatting.FormatAccent)" `
    "Added application 'demoapp-$demo' ($image)."