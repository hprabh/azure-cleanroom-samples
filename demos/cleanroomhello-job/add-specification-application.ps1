param(
    [string]$image = "docker.io/golang@sha256:f43c6f049f04cbbaeb28f0aad3eea15274a7d0a7899a617d0037aec48d7ab010",
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
    Write-Host "No action required for persona '$persona' in scenario '$scenario'."
    return
}

$cleanroomConfigResult = Get-Content $cleanroomConfig | ConvertFrom-Json

$inline_code = $(cat $PSScriptRoot/application/main.go | base64 -w 0)
az cleanroom config add-application `
    --cleanroom-config $cleanroomConfigResult.configFile `
    --name demoapp-$scenario `
    --image $image `
    --command "bash -c 'echo `$CODE | base64 -d > main.go; go run main.go'" `
    --mounts "src=fabrikam-input,dst=/mnt/remote/fabrikam-input" `
             "src=fabrikam-output,dst=/mnt/remote/fabrikam-output" `
    --env-vars OUTPUT_LOCATION=/mnt/remote/fabrikam-output `
               INPUT_LOCATION=/mnt/remote/fabrikam-input `
               CODE="$inline_code" `
    --cpu 0.5 `
    --memory 4
