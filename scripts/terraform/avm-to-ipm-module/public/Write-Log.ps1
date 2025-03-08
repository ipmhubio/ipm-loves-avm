function Write-Log {
  param (
      [Parameter(Mandatory = $true)]
      [string]$Message,

      [Parameter(Mandatory = $false)]
      [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS", "DEBUG")]
      [string]$Level = "INFO"
  )

  # Get call stack information
  $callStack = Get-PSCallStack
  $caller = $callStack[1] # Index 1 because 0 is the current function
  $fileName = if ($caller.ScriptName) { Split-Path -Leaf $caller.ScriptName } else { "Unknown" }
  $lineNumber = $caller.ScriptLineNumber

  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $logMessage = "[$timestamp] [$Level] [$fileName - $lineNumber] $Message"

  switch ($Level) {
      "INFO" {
          Write-Host $logMessage -ForegroundColor Cyan
      }
      "WARNING" {
          Write-Host $logMessage -ForegroundColor Blue
      }
      "ERROR" {
          Write-Host $logMessage -ForegroundColor Red
      }
      "SUCCESS" {
          Write-Host $logMessage -ForegroundColor Green
      }
      "DEBUG" {
          Write-Host $logMessage -ForegroundColor Yellow
      }
  }

  # Could also write to a log file if needed
  # Add-Content -Path "log.txt" -Value $logMessage
}