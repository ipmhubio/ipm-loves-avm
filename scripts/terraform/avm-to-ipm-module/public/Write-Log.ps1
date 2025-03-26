function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS", "DEBUG")]
        [string]$Level = "INFO",

        [Parameter(Mandatory = $false)]
        [string]$LogPath = "./logs/ipm-process.log"
    )

    # Create logs directory if it doesn't exist
    $logDirectory = Split-Path -Parent $LogPath
    if (-not (Test-Path -Path $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }

    # Get call stack information
    $callStack = Get-PSCallStack
    $caller = $callStack[1] # Index 1 because 0 is the current function
    $fileName = if ($caller.ScriptName) { Split-Path -Leaf $caller.ScriptName } else { "Unknown" }
    $lineNumber = $caller.ScriptLineNumber

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Format each column with fixed width
    $timestampCol = "{0,-19}" -f "[$timestamp]"
    $levelCol = "{0,-9}" -f "[$Level]"
    $locationCol = "{0,-30}" -f "[$fileName : $lineNumber]"

    $logMessage = "$timestampCol $levelCol $locationCol $Message"

    # Write to console with color
    switch ($Level) {
        "INFO" { Write-Host $logMessage -ForegroundColor Cyan }
        "WARNING" { Write-Host $logMessage -ForegroundColor Blue }
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        "DEBUG" { Write-Host $logMessage -ForegroundColor Yellow }
    }

    # Write to log file
    try {
        Add-Content -Path $LogPath -Value $logMessage -ErrorAction Stop
    }
    catch {
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
    }
}