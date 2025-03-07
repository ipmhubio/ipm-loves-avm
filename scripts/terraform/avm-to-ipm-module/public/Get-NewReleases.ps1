function Get-NewReleases {
  param (
      [string]$NewReleasesPath,
      [string]$CurrentStatePath,
      [string]$GithubToken
  )

  Write-Log "Identifying new packages and releases..."

  try {
      $outputPath = "diff.json"
      & "$PSScriptRoot/get-New-Packages-and-versions.ps1" -GithubToken $GithubToken -NewJsonPath $NewReleasesPath -ExistingJsonPath $CurrentStatePath -OutputJsonPath $outputPath

      if (Test-Path -Path $outputPath) {
          $diffContent = Get-Content -Path $outputPath -Raw | ConvertFrom-Json
          $newPackageCount = ($diffContent | Where-Object { $_.releases.Count -eq $_.release_count }).Count
          $updatedPackageCount = ($diffContent | Where-Object { $_.releases.Count -lt $_.release_count }).Count

          Write-Log "Found $newPackageCount new packages and $updatedPackageCount packages with updates" -Level "SUCCESS"
          return $outputPath
      }
      else {
          Write-Log "No new packages or releases found" -Level "INFO"
          return $null
      }
  }
  catch {
      Write-Log "Error identifying new releases: $_" -Level "ERROR"
      throw "Failed to identify new releases: $_"
  }
}
