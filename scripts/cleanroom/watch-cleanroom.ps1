param(
    [Parameter(Mandatory = $true)]
    [string]$contractId,

    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$cleanRoomName = "cleanroom-$contractId"
)

#https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Get-TimeStamp {
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

Write-Host -ForegroundColor DarkGray `
    "$(Get-TimeStamp) Waiting for clean room '$cleanRoomName' ('$resourceGroup')..."

do {
    $cleanroom = az container show --name $cleanRoomName --resource-group $resourceGroup
    $cleanroomState = $cleanroom | jq -r ".instanceView.state"

    # If the cleanroom deployment failed, exit.
    if ($cleanroomState -eq "Failed") {
        Write-Host -ForegroundColor Red `
            "$(Get-TimeStamp) Clean room '$cleanRoomName' has encountered an error."
        exit 1
    }
    elseif ($cleanroomState -eq "Running") {
        Write-Host -ForegroundColor DarkGray `
            "$(Get-TimeStamp) Clean room '$cleanRoomName' is running..."

        # Fetch the status of all the containers.
        $allcontainerStatus = $cleanroom | jq -r '.containers | .[] | .instanceView.currentState.detailStatus | select(length > 0)'

        # When all the containers are running, the detailStatus is not populated.
        if ($null -ne $allcontainerStatus -and $allcontainerStatus.Contains("Error")) {
            # TODO (phanic): Add details about the container that failed.
            Write-Host -ForegroundColor DarkGray `
                "$(Get-TimeStamp) Clean room '$cleanRoomName' has encountered an error in one " `
                "or more containers."
            exit 1
        }

        # Fetch code launcher sidecar status.
        $codeLauncherState = $cleanroom | jq '.containers | .[] | select(.name | contains("code-launcher")) | .instanceView.currentState' | ConvertFrom-Json
        if ($codeLauncherState.state -eq "Running") {
            Write-Host -ForegroundColor DarkGray `
                "$(Get-TimeStamp) Clean room application is running..."
        }
        elseif ($codeLauncherState.state -eq "Terminated") {
            Write-Host -ForegroundColor Yellow `
                "$(Get-TimeStamp) Clean room application has terminated. Checking exit code..."
            $exitCode = $codeLauncherState.exitCode
            if ($exitCode -ne 0) {
                Write-Host -ForegroundColor Red `
                    "$(Get-TimeStamp) Clean room application exited with non-zero exit code '$exitCode'."
                exit $exitCode
            }
            else {
                Write-Host -ForegroundColor Green `
                    "$(Get-TimeStamp) Clean room application exited successfully."
                exit 0
            }
        }
        else {
            Write-Host -ForegroundColor Yellow `
                "$(Get-TimeStamp) Clean room application is in state '$($codeLauncherState.state)'"
        }
    }
    else {
        Write-Host -ForegroundColor Yellow `
            "$(Get-TimeStamp) Clean room '$cleanRoomName' is in state '$cleanroomState'"
    }

    Write-Host -ForegroundColor DarkGray `
        "$(Get-TimeStamp) Waiting for 20 seconds before checking status again..."
    Start-Sleep -Seconds 20
} while ($true)
