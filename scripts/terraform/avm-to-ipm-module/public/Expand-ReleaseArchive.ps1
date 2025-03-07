function Expand-ReleaseArchive {
  param (
      [string]$ArchivePath,
      [string]$DestinationPath
  )

  try {
      # Create extraction directory
      if (-not (Test-Path -Path $DestinationPath)) {
          New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
      }

      # Extract the tar.gz file
      if ($ArchivePath.EndsWith(".tar.gz") -or $ArchivePath.EndsWith(".tgz")) {
          # For tar.gz files, we need a two-step approach in Windows PowerShell
          $tempPath = "$DestinationPath\temp"
          New-Item -Path $tempPath -ItemType Directory -Force | Out-Null

          # First, extract the .gz file
          $tarFile = "$tempPath\archive.tar"
          Copy-Item -Path $ArchivePath -Destination $tarFile

          # Use the tar command (available in newer Windows versions)
          tar -xf $tarFile -C $DestinationPath

          # Clean up
          Remove-Item -Path $tempPath -Recurse -Force
      }
      else {
          # For zip files
          Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force
      }

      return $true
  }
  catch {
      Write-Log "Failed to extract archive $ArchivePath : $_" -Level "ERROR"
      return $false
  }
}