function Get-AzureAvmReleases {
  param (
      [Parameter(Mandatory = $true)]
      [string]$githubToken,
      [string]$outputPath
  )
  Write-Log "Fetching AVM releases from GitHub..."

  #validate if the output path json file exists, than exit function because we already have the releases
  if (Test-Path -Path $outputPath) {
      Write-Log "AVM releases already retrieved" -Level "INFO"
      return $outputPath
  }

  try {
      # Run the existing script to get releases
      & "$PSScriptRoot/get-avmRepoReleases.ps1" -GithubToken $GithubToken

      # Verify the output file was created
      if (-not (Test-Path -Path $tempOutputPath)) {
          Write-Log "Failed to create output file from get-avmRepoReleases.ps1" -Level "ERROR"
          throw "Failed to retrieve AVM releases"
      }

      Write-Log "Successfully retrieved AVM releases" -Level "SUCCESS"
      return $tempOutputPath
  }
  catch {
      Write-Log "Error retrieving AVM releases: $_" -Level "ERROR"
      throw "Failed to retrieve AVM releases: $_"
  }
}
