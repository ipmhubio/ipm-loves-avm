function Publish-ToIpm {
  param (
      [string]$PackagePath,
      [string]$PackageName,
      [string]$Version
  )

  try {
      Write-Log "Publishing $PackageName v$Version to IPM..." -Level "INFO"

      # This is a placeholder for your actual IPM publish command
      # Replace with your actual command to publish to IPM
      $process = Start-Process -FilePath $IpmClientPath -ArgumentList "publish", "--folder", $PackagePath, "--package", $PackageName, "--version", $Version --non-interactive -PassThru -Wait

      if ($process.ExitCode -ne 0) {
          Write-Log "Failed to publish $PackageName v$Version to IPM" -Level "ERROR"
          return $false
      }

      Write-Log "Successfully published $PackageName v$Version to IPM" -Level "SUCCESS"
      return $true
  }
  catch {
      Write-Log "Error publishing to IPM: $_" -Level "ERROR"
      return $false
  }
}