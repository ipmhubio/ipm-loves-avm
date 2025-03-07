function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "INFO" { Write-Host $logMessage -ForegroundColor Cyan }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
    }

    # Could also write to a log file if needed
    # Add-Content -Path "log.txt" -Value $logMessage
}

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

function Update-ModuleDocumentation {
    param (
        [string]$ModulePath
    )

    # try {
    #     # Assume the module might have a terraform-docs.yml file that controls doc generation
    #     # If not, you might need to create one

    #     # Check if terraform-docs is installed
    #     $terraformDocsInstalled = $null -ne (Get-Command terraform-docs -ErrorAction SilentlyContinue)

    #     if (-not $terraformDocsInstalled) {
    #         Write-Log "terraform-docs tool not found. Documentation won't be updated." -Level "WARNING"
    #         return $true
    #     }

    #     # Run terraform-docs to update documentation
    #     $process = Start-Process -FilePath "terraform-docs" -ArgumentList "markdown", "table", "--output-file", "README.md", $ModulePath -NoNewWindow -PassThru -Wait

    #     if ($process.ExitCode -ne 0) {
    #         Write-Log "Failed to update documentation for $ModulePath" -Level "WARNING"
    #         return $false
    #     }

    #     return $true
    # }
    # catch {
    #     Write-Log "Error updating documentation for $ModulePath : $_" -Level "ERROR"
    #     return $false
    # }
}

function Test-TerraformModule {
    param (
        [string]$ModulePath
    )

    # Change to module directory
    $currentLocation = Get-Location
    try {
        Set-Location -Path $ModulePath

        # Run terraform init
        Write-Log "Running terraform init for $ModulePath..." -Level "INFO"
        $initProcess = Start-Process -FilePath "terraform" -ArgumentList "init", "-no-color" -NoNewWindow -PassThru -Wait -RedirectStandardOutput "terraform_init.log" -RedirectStandardError "terraform_init_error.log"

        if ($initProcess.ExitCode -ne 0) {
            Write-Log "Terraform init failed for $ModulePath" -Level "ERROR"
            return $false
        }

        # Run terraform validate
        Write-Log "Running terraform validate for $ModulePath..." -Level "INFO"
        $validateProcess = Start-Process -FilePath "terraform" -ArgumentList "validate", "-no-color" -NoNewWindow -PassThru -Wait -RedirectStandardOutput "terraform_validate.log" -RedirectStandardError "terraform_validate_error.log"

        if ($validateProcess.ExitCode -ne 0) {
            Write-Log "Terraform validate failed for $ModulePath" -Level "ERROR"
            return $false
        }

        # Run terraform fmt
        Write-Log "Running terraform fmt for $ModulePath..." -Level "INFO"
        $fmtProcess = Start-Process -FilePath "terraform" -ArgumentList "fmt", "-no-color", "-recursive" -NoNewWindow -PassThru -Wait

        # fmt returns 0 if no changes were made, 1 if changes were made, and 2+ if there was an error
        if ($fmtProcess.ExitCode -gt 1) {
            Write-Log "Terraform fmt encountered errors for $ModulePath" -Level "ERROR"
            return $false
        }

        return $true
    }
    catch {
        Write-Log "Error testing Terraform module $ModulePath : $_" -Level "ERROR"
        return $false
    }
    finally {
        # Return to original location
        Set-Location -Path $currentLocation
    }
}

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

function Send-TeamsNotification {
    param (
        [string]$Message = "No message provided",
        [string]$Title = "AVM Package Processing Report",
        [string]$Color = "0078D7" # Default blue
    )

    if ([string]::IsNullOrEmpty($TeamsWebhookUrl)) {
        Write-Log "Teams webhook URL not provided. Skipping notification." -Level "WARNING"
        return
    }

    try {
        $payload = @{
            "@type"      = "MessageCard"
            "@context"   = "http://schema.org/extensions"
            "themeColor" = $Color
            "title"      = $Title
            "text"       = $Message
        }

        $body = ConvertTo-Json -InputObject $payload -Depth 4

        Invoke-RestMethod -Uri $TeamsWebhookUrl -Method Post -Body $body -ContentType 'application/json'
        Write-Log "Teams notification sent successfully" -Level "SUCCESS"
    }
    catch {
        Write-Log "Failed to send Teams notification: $_" -Level "ERROR"
    }
}

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

# Add the function to the exported members list

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


# Publish to IPM
Write-Log "Publishing $packageName v$version to IPM..." -Level "INFO"
#$publishSuccess = Publish-ToIpm -PackagePath $moduleDir -PackageName $packageName -Version $version
$publishSuccess = $true # Temporary fix - replace with actual publishing code

if (-not $publishSuccess) {
    Write-Log "Failed to publish $packageName v$version to IPM" -Level "ERROR"
    return $false
}

Write-Log "Successfully processed $packageName v$version" -Level "SUCCESS"
return $true

export-modulemember -function Write-Log, Initialize-Environment, Get-AzureAvmReleases, Get-NewReleases, Get-ReleaseArchive, Expand-ReleaseArchive, Update-ModuleDocumentation, Test-TerraformModule, Publish-ToIpm, Send-TeamsNotification, Invoke-AvmRelease, Get-avmRepoReleases
