enum LogLevel {
    Critical
    Error
    Warning
    OperationCompleted
    OperationStarted
    Information
    Verbose
}

function Write-Log {
    param (
        [LogLevel] $Level,
        [string] $Message
    )

    $formatting = switch ($Level)
    {
        Critical {"$($PSStyle.Formatting.ErrorAccent)"}
        Error { "$($PSStyle.Formatting.Error)" }
        Warning { "$($PSStyle.Formatting.Warning)" }
        OperationCompleted {"$($PSStyle.Formatting.FormatAccent)"}
        OperationStarted {"$($PSStyle.Formatting.CustomTableHeaderLabel)"}
        Information {"$($PSStyle.Dim)"}
        Verbose {"$($PSStyle.Dim)$($PSStyle.Italic)"}
        default { "$($PSStyle.Reset)" }
    }

    Write-Host "$formatting$Message$($PSStyle.Reset)"
}

function Test-Log {
    $levels = [LogLevel].GetEnumValues()
    foreach ($level in $levels)
    {
        Write-Log $level "Logging '$level'"
    }
}
