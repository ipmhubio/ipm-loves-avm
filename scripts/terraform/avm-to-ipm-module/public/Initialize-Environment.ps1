function Initialize-Environment {
  [CmdletBinding()]
  param (
      [Parameter(Mandatory = $true)]
      [string]$StagingDirectory,
      [Parameter(Mandatory = $true)]
      [string]$StateFilePath
  )
  Write-Log "Initializing environment..."

  # Create staging directory if it doesn't exist
  if (-not (Test-Path -Path $StagingDirectory)) {
      New-Item -Path $StagingDirectory -ItemType Directory | Out-Null
      Write-Log "Created staging directory: $StagingDirectory" -Level "INFO"
  }

  # Check if we have previous state file
  if (-not (Test-Path -Path $StateFilePath)) {
      Write-Log "No previous state file found. Need to create a new one" -Level "WARNING"
      $initialState = @()
      $initialState | ConvertTo-Json -Depth 5 | Out-File -FilePath $StateFilePath
  }

  # Validate IPM client exists if specified

  try {
      $ipmVersion = & ipm --version
      Write-Log "IPM client version: $ipmVersion" -Level "INFO"
  }
  catch {
      Write-Log "Failed to run IPM client. Please ensure it is installed and accessible." -Level "ERROR"
      throw "IPM client validation failed"
  }

  Write-Log "Environment initialization complete" -Level "SUCCESS"
}