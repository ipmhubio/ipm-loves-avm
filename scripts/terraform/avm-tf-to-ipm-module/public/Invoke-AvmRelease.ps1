function Copy-ExtractedToIpmBuild
{
    param (
        [string]$ExtractedPath,
        [string]$VersionFolderPath
    )

    # Create build-for-ipm folder at the same level as extracted and release.tar.gz
    $buildForIpmPath = Join-Path (Split-Path $VersionFolderPath -Parent) "build-for-ipm"
    if (Test-Path $buildForIpmPath)
    {
        Remove-Item -Path $buildForIpmPath -Recurse -Force
    }
    New-Item -Path $buildForIpmPath -ItemType Directory -Force | Out-Null

    # Get all items from extracted folder, excluding dot folders
    Get-ChildItem -Path $ExtractedPath -Recurse | Where-Object {
        # Exclude dot folders and their contents
        $_.FullName -notmatch '\\\..*\\' -and
        # Exclude .terraform folder
        $_.FullName -notmatch '\\\.terraform\\' -and
        # Exclude tests folder
        $_.FullName -notmatch '\\tests\\' -and
        # Exclude avm.bat
        $_.Name -ne 'avm.bat' -and
        # Exclude .log files
        $_.Extension -ne '.log' -and
        # exclude Makefile, avm CODE_OF_CONDUCT.md
        $_.Name -notmatch 'Makefile|CODE_OF_CONDUCT.md' -and
        # Exclude dot folders at root level
        $_.Name -notmatch '^\.'
    } | ForEach-Object {
        $relativePath = $_.FullName.Substring($ExtractedPath.Length + 1)
        $targetPath = Join-Path $buildForIpmPath $relativePath

        if ($_.PSIsContainer)
        {
            New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
        }
        else
        {
            $targetDir = Split-Path $targetPath -Parent
            if (-not (Test-Path $targetDir))
            {
                New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path $_.FullName -Destination $targetPath -Force
        }
    }

    return $buildForIpmPath
}

function Invoke-AvmRelease
{
    param (
        [PSCustomObject]$Package,
        [PSCustomObject]$Release,
        [string]$StagingRoot,
        [string]$GithubToken,
        [switch]$Force = $false,
        [switch]$LocalRun = $false,
        [bool]$skipTests = $false
    )

    $packageName = $Package.name
    $version = $Release.version
    $tarballUrl = $Release.tarball_url

    Write-Log "Processing $packageName v$version..." -Level "INFO"

    # Initialize result hashtable
    $result = @{
        Success = $false
        Done    = $false
        Message = ""
    }

    # Use the new Get-AvmTerraformModule function to download and extract
    $moduleResult = Get-AvmTerraformModule -PackageName $packageName -Version $version -TarballUrl $tarballUrl `
        -StagingDirectory $StagingRoot -GithubToken $GithubToken -Force:$Force

    if (-not $moduleResult.Success)
    {
        $result.Message = "Failed to download or extract $packageName v$version : $($moduleResult.Message)"
        Write-Log $result.Message -Level "ERROR"
        return $result
    }

    # Create build-for-ipm folder and copy files
    $buildForIpmPath = Copy-ExtractedToIpmBuild -ExtractedPath $moduleResult.ModulePath -VersionFolderPath (Split-Path $moduleResult.ModulePath -Parent)

    # From here on, use $buildForIpmPath instead of $moduleDir for further processing
    # Update documentation
    Write-Log "Updating documentation for $packageName v$version..." -Level "INFO"
    $docUpdateSuccess = Update-ModuleDocumentation -ModulePath $buildForIpmPath -PackageName $packageName -Version $version

    if (-not $docUpdateSuccess)
    {
        Write-Log "Warning: Documentation update failed for $packageName v$version" -Level "WARNING"
        # Continue processing despite documentation issues
    }

    #Change telemetry settings
    Write-Log "Updating telemetry settings for $packageName v$version..." -Level "INFO"

    @(
        @{
            Action         = { Update-TelemetryDefault -Path $buildForIpmPath }
            SuccessMessage = "Successfully updated telemetry settings"
            WarningMessage = "Failed to update telemetry settings"
        },
        @{
            Action            = { Update-TelemetryDefaultInMarkdown -Path $buildForIpmPath }
            SuccessMessage    = "Successfully updated telemetry documentation"
            WarningMessage    = "Failed to update telemetry documentation"
            DependsOnPrevious = $true
        }
    ) | ForEach-Object {
        $result = $true
        if (-not $_.DependsOnPrevious -or $result)
        {
            $result = & $_.Action
            $message = if ($result) { $_.SuccessMessage } else { $_.WarningMessage }
            Write-Log "$message for $packageName v$version" -Level $(if ($result) { "INFO" } else { "WARNING" })
        }
        $result
    }
    # add disclaimer file
    Write-Log "Adding disclaimer file for $repoName version $version" -Level "INFO"
    Add-DisclaimerFile -PackageName $package.name -Path $buildForIpmPath

    # Test Terraform module
    if ($skipTests)
    {
        Write-Log "Skipping Terraform validation for $packageName v$version" -Level "INFO"
        $testSuccess = $true
    }
    else
    {
        Write-Log "Testing $packageName v$version with Terraform..." -Level "INFO"
        $testSuccess = Test-TerraformModule -ModulePath $buildForIpmPath
    }

    if ($testSuccess -eq $false)
    {
        $result = [PSCustomObject]@{
            Success = $false
            Message = ""
        }
        $result.Message = "Terraform validation failed for $($packageName) v$($version)"
        Write-Log $result.Message -Level "WARNING"
        return $result
    }

    # Check if running locally
    # $isLocalRun = [bool]($env:LOCAL_RUN)

    # Publish to IPM
    # $publishResult = Publish-ToIpm `
    #     -PackagePath $buildForIpmPath `
    #     -PackageName $packageName `
    #     -ipmOrganization $ipmOrganization `
    #     -Version $version `
    #     -LocalRun $isLocalRun
    # Write-Log "!Publish result: $($publishResult | ConvertTo-Json -Depth 10)" -Level "INFO"

    # if ($publishResult.Success -eq $false)
    # {
    #     $result.Success = $false
    #     $result.Message = "Failed to publish $packageName v$version"
    #     Write-Log $result.Message -Level "ERROR"
    #     return $result
    # }
    Write-Log "Done processing $packageName v$version" -Level "INFO"

    # Set success message before returning
    $result = [PSCustomObject]@{
        Success = $true
        Message = ""
    }
    $result.Success = $true
    $result.Message = "Successfully processed $packageName v$version"
    Write-Log $result.Message -Level "SUCCESS"
    return $result
}