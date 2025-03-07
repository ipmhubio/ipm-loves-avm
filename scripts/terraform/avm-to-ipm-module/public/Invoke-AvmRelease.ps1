function Invoke-AvmRelease {
  param (
      [PSCustomObject]$Package,
      [PSCustomObject]$Release,
      [string]$StagingRoot,
      [string]$GithubToken,
      [switch]$Force = $false
  )

  $packageName = $Package.name
  $version = $Release.version
  $tarballUrl = $Release.tarball_url

  Write-Log "Processing $packageName v$version..." -Level "INFO"

  # Use the new Get-AvmTerraformModule function to download and extract
  $moduleResult = Get-AvmTerraformModule -PackageName $packageName -Version $version -TarballUrl $tarballUrl `
      -StagingDirectory $StagingRoot -GithubToken $GithubToken -Force:$Force

  if (-not $moduleResult.Success) {
      Write-Log "Failed to download or extract $packageName v $version : $($moduleResult.Message)" -Level "ERROR"
      return $false
  }

  $moduleDir = $moduleResult.ModulePath

  # If the module already existed and we're not forcing a redownload, we might still want to continue processing
  # Depending on your requirements, you might want to skip the remaining steps if AlreadyExists is true

  # Update documentation
  Write-Log "Updating documentation for $packageName v$version..." -Level "INFO"
  $docUpdateSuccess = Update-ModuleDocumentation -ModulePath $moduleDir

  if (-not $docUpdateSuccess) {
      Write-Log "Warning: Documentation update failed for $packageName v$version" -Level "WARNING"
      # Continue processing despite documentation issues
  }

  # Test Terraform module
  Write-Log "Testing $packageName v$version with Terraform..." -Level "INFO"
  $testSuccess = Test-TerraformModule -ModulePath $moduleDir

  if (-not $testSuccess) {
      Write-Log "Terraform validation failed for $packageName v$version" -Level "ERROR"
      return $false
  }
}