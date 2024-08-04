function Replace-Strings {
    param (
        [string]$filePath,
        
        [hashtable]$replacements
    )

    $fileContent = Get-Content -Path $((Resolve-Path $filePath).Path)
    $content = ''
    foreach ($line in $fileContent) {
        $content = $content + [environment]::NewLine + $line
    }

    foreach ($key in $replacements.Keys) {
        $content = $content -replace $key, $replacements[$key]
    }
    return $content
}

function CheckLastExitCode() {
    if ($LASTEXITCODE -gt 0) { exit 1 }
}

function Get-ContainerRegistryUrl {

    if ([System.String]::IsNullOrEmpty($env:CONTAINER_REGISTRY_URL)) {
        return "mcr.microsoft.com/cleanroom"
    }
    else {
        return $env:CONTAINER_REGISTRY_URL
    }
}

function Get-ContainerDigestTag {
    if ($env:GITHUB_ACTIONS -eq "true") {
        return $env:IMAGE_TAG
    }

    return "latest"
}