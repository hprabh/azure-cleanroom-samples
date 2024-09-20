param(
    [Parameter(Mandatory = $true)]
    [string]$contractId,

    [string]$resourceGroup = "$env:RESOURCE_GROUP",

    [string]$cleanRoomName = "cleanroom-$contractId"
)

$ErrorActionPreference = 'Stop'

function Get-TimeStamp {
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

Write-Host "$(Get-TimeStamp) Waiting for clean room $cleanRoomName in resource group $resourceGroup"

do {
    $cleanroom = az container show --name $cleanRoomName --resource-group $resourceGroup
    $cleanroomState = $cleanroom | jq -r ".instanceView.state"
    # If the cleanroom deployment failed, exit.
    if ($cleanroomState -eq "Failed") {
        Write-Host -ForegroundColor DarkRed "$(Get-TimeStamp) Cleanroom has failed. Exiting."
        exit 1
    }
    elseif ($cleanroomState -eq "Running") {
        Write-Host -ForegroundColor DarkGreen "$(Get-TimeStamp) Cleanroom is running..."

        # Fetch the status of all the containers.
        $allcontainerStatus = $cleanroom | jq -r '.containers | .[] | .instanceView.currentState.detailStatus | select(length > 0)'

        # When all the containers are running, the detailStatus is not populated.
        if ($null -ne $allcontainerStatus -and $allcontainerStatus.Contains("Error")) {
            Write-Host -ForegroundColor DarkRed "$(Get-TimeStamp) Cleanroom has encountered an error. Exiting."
            exit 1
        }

        # Fetch code launcher sidecar status.
        $codeLauncherState = $cleanroom | jq '.containers | .[] | select(.name | contains("code-launcher")) | .instanceView.currentState' | ConvertFrom-Json
        if ($codeLauncherState.state -eq "Running") {
            Write-Host -ForegroundColor Green "$(Get-TimeStamp) Code launcher is running..."
        }
        elseif ($codeLauncherState.state -eq "Terminated") {
            Write-Host -ForegroundColor Yellow "$(Get-TimeStamp) Code launcher is terminated. Checking exit code."
            $exitCode = $codeLauncherState.exitCode
            if ($exitCode -ne 0) {
                Write-Host -ForegroundColor DarkRed "$(Get-TimeStamp) Code launcher exited with non-zero exit code $exitCode"
                exit $exitCode
            }
            else {
                Write-Host -ForegroundColor DarkGreen "$(Get-TimeStamp) Code launcher exited successfully."
                exit 0
            }
        }
        else {
            Write-Host -ForegroundColor Yellow "$(Get-TimeStamp) Code launcher is in state $($codeLauncherState.state)"
        }
    }
    else {
        Write-Host -ForegroundColor Yellow "$(Get-TimeStamp) Cleanroom is in state $cleanroomState"
    }

    Write-Host "$(Get-TimeStamp) Waiting for 20 seconds before checking status again..."
    Start-Sleep -Seconds 20
} while ($true)
