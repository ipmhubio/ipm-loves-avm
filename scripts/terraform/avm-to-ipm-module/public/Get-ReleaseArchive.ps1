function Get-ReleaseArchive {
  param (
      [string]$DownloadUrl,
      [string]$DestinationPath
  )

  try {
      $headers = @{
          'Accept'        = 'application/vnd.github+json'
          'Authorization' = "Bearer $GithubToken"
      }

      Invoke-WebRequest -Uri $DownloadUrl -Headers $headers -OutFile $DestinationPath
      return $true
  }
  catch {
      Write-Log "Failed to download archive from $DownloadUrl : $_" -Level "ERROR"
      return $false
  }
}
