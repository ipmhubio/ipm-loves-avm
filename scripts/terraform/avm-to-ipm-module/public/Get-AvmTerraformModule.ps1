function Get-AvmTerraformModule {
  <#
  .SYNOPSIS
      Downloads and extracts an Azure Verified Module (AVM) Terraform package.

  .DESCRIPTION
      Downloads a Terraform module from Azure Verified Modules repository using a tarball URL.
      Creates appropriate folder structure in the staging directory (repo/version).
      Extracts the module files and handles both .tar.gz and .zip archives.
      Skips download if files already exist unless Force parameter is specified.

  .PARAMETER PackageName
      The name of the Terraform module package.

  .PARAMETER Version
      Version of the package to download.

  .PARAMETER TarballUrl
      URL to download the package tarball.

  .PARAMETER StagingDirectory
      Root directory where packages will be stored.

  .PARAMETER GithubToken
      GitHub personal access token for authentication.

  .PARAMETER Force
      If specified, overwrites existing files even if they already exist.

  .OUTPUTS
      PSObject containing extraction results with these properties:
      - Success: Boolean indicating if the operation succeeded
      - ModulePath: Path to the extracted module directory
      - PackageDirectory: Path to the package directory
      - VersionDirectory: Path to the specific version directory
  #>
  [CmdletBinding()]
  param (
      [Parameter(Mandatory = $true)]
      [string]$PackageName,

      [Parameter(Mandatory = $true)]
      [string]$Version,

      [Parameter(Mandatory = $true)]
      [string]$TarballUrl,

      [Parameter(Mandatory = $true)]
      [string]$StagingDirectory,

      [Parameter(Mandatory = $true)]
      [string]$GithubToken,

      [Parameter(Mandatory = $false)]
      [switch]$Force
  )

  # Initialize result object
  $result = [PSCustomObject]@{
      Success          = $false
      ModulePath       = $null
      PackageDirectory = $null
      VersionDirectory = $null
      AlreadyExists    = $false
      Message          = ""
  }

  try {
      # Create the folder structure
      $packageDir = Join-Path -Path $StagingDirectory -ChildPath $PackageName
      $versionDir = Join-Path -Path $packageDir -ChildPath $Version
      $extractPath = Join-Path -Path $versionDir -ChildPath "extracted"
      $archivePath = Join-Path -Path $versionDir -ChildPath "release.tar.gz"

      $result.PackageDirectory = $packageDir
      $result.VersionDirectory = $versionDir

      # Check if the extracted module already exists
      if ((Test-Path -Path $extractPath) -and (Get-ChildItem -Path $extractPath -Directory).Count -gt 0) {
          $existingModule = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1

          if (-not $Force) {
              Write-Log "Module $PackageName v$Version already exists at $($existingModule.FullName). Use -Force to overwrite." -Level "INFO"
              $result.Success = $true
              $result.AlreadyExists = $true
              $result.ModulePath = $existingModule.FullName
              $result.Message = "Module already exists"
              return $result
          }
          else {
              Write-Log "Forcing re-download of $PackageName v$Version" -Level "INFO"
              # Clean existing directory when Force is specified
              Get-ChildItem -Path $versionDir | Remove-Item -Recurse -Force
          }
      }

      # Create directories if they don't exist
      if (-not (Test-Path -Path $packageDir)) {
          New-Item -Path $packageDir -ItemType Directory -Force | Out-Null
          Write-Log "Created package directory: $packageDir" -Level "INFO"
      }

      if (-not (Test-Path -Path $versionDir)) {
          New-Item -Path $versionDir -ItemType Directory -Force | Out-Null
          Write-Log "Created version directory: $versionDir" -Level "INFO"
      }

      # Download the tarball
      Write-Log "Downloading $PackageName v$Version from $TarballUrl..." -Level "INFO"

      $headers = @{
          'Accept'        = 'application/vnd.github+json'
          'Authorization' = "Bearer $GithubToken"
      }

      try {
          Invoke-WebRequest -Uri $TarballUrl -Headers $headers -OutFile $archivePath
      }
      catch {
          Write-Log "Failed to download archive from $TarballUrl : $_" -Level "ERROR"
          $result.Message = "Download failed: $_"
          return $result
      }

      # Create extraction directory
      if (-not (Test-Path -Path $extractPath)) {
          New-Item -Path $extractPath -ItemType Directory -Force | Out-Null
      }

      # Extract the archive
      Write-Log "Extracting $PackageName v$Version..." -Level "INFO"

      try {
          # Extract based on file type
          if ($archivePath.EndsWith(".tar.gz") -or $archivePath.EndsWith(".tgz")) {
              # For tar.gz files, use a two-step approach
              $tempPath = Join-Path -Path $versionDir -ChildPath "temp"
              New-Item -Path $tempPath -ItemType Directory -Force | Out-Null

              # On macOS and Linux, use tar directly
              if ($IsMacOS -or $IsLinux) {
                  $tarResult = tar -xzf $archivePath -C $extractPath
                  if ($LASTEXITCODE -ne 0) {
                      throw "tar extraction failed with exit code $LASTEXITCODE"
                  }
              }
              else {
                  # On Windows, may need to use a different approach depending on available tools
                  $tarFile = Join-Path -Path $tempPath -ChildPath "archive.tar"

                  # Try to use tar if available (Windows 10 1803+ has it built-in)
                  if (Get-Command -Name tar -ErrorAction SilentlyContinue) {
                      $tarResult = tar -xzf $archivePath -C $extractPath
                      if ($LASTEXITCODE -ne 0) {
                          throw "tar extraction failed with exit code $LASTEXITCODE"
                      }
                  }
                  else {
                      # Fallback for older Windows versions
                      # This requires additional tools that may not be available
                      throw "tar command not available. Please install tar or use a supported platform."
                  }
              }

              # Clean up temp directory if created
              if (Test-Path -Path $tempPath) {
                  Remove-Item -Path $tempPath -Recurse -Force
              }
          }
          else {
              # For zip files
              Expand-Archive -Path $archivePath -DestinationPath $extractPath -Force
          }
      }
      catch {
          Write-Log "Failed to extract archive $archivePath : $_" -Level "ERROR"
          $result.Message = "Extraction failed: $_"
          return $result
      }

      # Find the module directory (usually one level below extraction)
      $moduleDirectory = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1

      if ($null -eq $moduleDirectory) {
          Write-Log "No module directory found in extracted contents" -Level "ERROR"
          $result.Message = "No module directory found in extracted contents"
          return $result
      }

      $result.Success = $true
      $result.ModulePath = $moduleDirectory.FullName
      $result.Message = "Successfully downloaded and extracted module"

      Write-Log "Successfully downloaded and extracted $PackageName v$Version to $($moduleDirectory.FullName)" -Level "SUCCESS"
      return $result
  }
  catch {
      "Error in Get-AvmTerraformModule for $PackageName v${0}: $_" -f $version | Write-Log -Level "ERROR"
      $result.Message = "Error: $_"
      return $result
  }
}