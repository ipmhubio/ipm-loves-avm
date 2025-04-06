
<#
.SYNOPSIS
    Tests downloaded Azure Verified Modules (AVM) Terraform packages.
.DESCRIPTION
    This script identifies packages in the Downloaded state and runs Terraform validation
    tests on them, updating their status to Tested or Failed accordingly.
.PARAMETER StorageAccountName
    Azure Storage Account Name for state management.
.PARAMETER StorageAccountKey
    Azure Storage Account Key for state management.
.PARAMETER TableName
    Azure Storage Table Name for state management.
.PARAMETER StagingDirectory
    Directory where packages are downloaded and processed.
.PARAMETER TeamsWebhookUrl
    Microsoft Teams webhook URL for status reporting.
.PARAMETER UseAzurite
    Boolean flag to indicate if Azurite should be used for local development.
.PARAMETER SkipTests
    Boolean flag to skip actual terraform testing (for development purposes).
#>

[CmdletBinding()]
param (

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName = "devstoreaccount1",

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountKey = "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==",

    [Parameter(Mandatory = $false)]
    [string]$StorageSasToken,

    [Parameter(Mandatory = $false)]
    [string]$TableName = "AvmPackageVersions",

    [Parameter(Mandatory = $false)]
    [string]$TableNameReleaseNotes = "AvmPackageReleaseNotes",

    [Parameter(Mandatory = $false)]
    [string]$StagingDirectory = "staging",

    [Parameter(Mandatory = $false)]
    [string]$TeamsWebhookUrl,

    [Parameter(Mandatory = $false)]
    [bool]$UseAzurite = $true,

    [Parameter(Mandatory = $false)]
    [bool]$SkipTests = $false
)

# Import required modules and types
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "avm-tf-to-ipm-module/avm-tf-to-ipm-module.psm1") -Force


#region Main Execution
$ErrorActionPreference = "Stop"
$testedCount = 0
$failedCount = 0
$failedPackages = @()

try
{

    # Verify staging directory exists
    if (-not (Test-Path $StagingDirectory))
    {
        Write-Log "Staging directory does not exist: $StagingDirectory" -Level "ERROR"
        throw "Staging directory not found"
    }

    # Instead of getting packages from the table, scan the staging directory for packages
    $packages = Get-ChildItem -Path $StagingDirectory -Directory
    $packagesToTest = @()

    foreach ($packageDir in $packages)
    {
        $packageName = $packageDir.Name
        Write-Log "Processing package directory: $packageName" -Level "INFO"

        # Get all version directories for this package
        $versionDirs = Get-ChildItem -Path $packageDir.FullName -Directory
        Write-Log "Found $($versionDirs.Count) version directories for package: $packageName" -Level "INFO"

        # Sort version directories by semantic version (lowest first)
        $versionDirs = $versionDirs | Sort-Object {
            $version = $_.Name -replace '^v', '' # Remove leading 'v' if present
            $versionParts = $version.Split('.')

            # Create a sortable array of integers (padding with zeros for comparison)
            $major = [int]($versionParts[0] ?? 0)
            $minor = [int]($versionParts[1] ?? 0)
            $patch = [int]($versionParts[2] ?? 0)

            # Return a composite sortable value
            return ($major * 1000000) + ($minor * 1000) + $patch
        }

        Write-Log "Sorted version directories: $($versionDirs.Name -join ', ')" -Level "INFO"

        foreach ($versionDir in $versionDirs)
        {
            $version = $versionDir.Name
            Write-Log "Processing version directory: $version for package: $packageName" -Level "INFO"

            # Check if the build-for-ipm folder exists in this version directory
            $buildForIpmPath = Join-Path -Path $versionDir.FullName -ChildPath "build-for-ipm"
            Write-Log "Checking for build-for-ipm folder at path: $buildForIpmPath" -Level "INFO"

            if (Test-Path $buildForIpmPath)
            {
                Write-Log "Found build-for-ipm folder for package: $packageName version: $version" -Level "SUCCESS"
                $packagesToTest += [PSCustomObject]@{
                    PackageName = $packageName
                    Version     = $version
                    Path        = $buildForIpmPath
                }
            }
            else
            {
                Write-Log "build-for-ipm folder not found for package: $packageName version: $version" -Level "WARNING"
            }
        }
    }
    Write-Log "Found $($packagesToTest.Count) packages to test" -Level "INFO"

    # Get all packages with 'Downloaded' status from the table
    $downloadedPackages = Get-TableEntities -Table $table | Where-Object { $_.Status -eq "Downloaded" -or $_.Status -eq "Failed"}
    Write-Log "Found $($downloadedPackages.Count) packages with 'Downloaded' status in the table" -Level "INFO"
    WRITE-LOG "Downloaded packages: $($downloadedPackages | ConvertTo-Json -Depth 10)" -Level "DEBUG"
    foreach ($package in $packagesToTest)
    {
        $packageName = $package.PackageName
        $version = $package.Version
        $packagePath = $package.Path
        # Check if this package is in the downloaded packages list
        $versionDash = $version.Replace(".", "-") # Convert version to match table format
        $matchingTableEntry = $downloadedPackages | Where-Object {
            $_.PartitionKey -ieq $packageName -and $_.RowKey -ieq $versionDash
        }

        if (-not $matchingTableEntry)
        {
            Write-Log "Skipping package: $packageName version: $version - not in 'Downloaded' status in the table" -Level "INFO"
            continue
        }

        Write-Log "Testing package: $packageName version: $version" -Level "INFO"

        # Update state to Testing
        Update-PackageVersionState -Table $table -PackageName $packageName -Version $version -Status "Testing"

        # Package path is directly from our directory scan
        if (-not (Test-Path $packagePath))
        {
            Write-Log "Package path does not exist: $packagePath" -Level "ERROR"
            Update-PackageVersionState -Table $table -PackageName $packageName -Version $version -Status "Failed" -ErrorMessage "Package path not found"
            $failedCount++
            $failedPackages += "$packageName v$version"
            continue
        }

        # Test the terraform module
        $testSuccess = $true
        if (-not $SkipTests)
        {
            Write-Log "Running terraform validation for $packageName v$version" -Level "INFO"
            $testSuccess = Test-TerraformModule -ModulePath $packagePath
        }
        else
        {
            Write-Log "Skipping terraform validation for $packageName v$version" -Level "INFO"
        }

        # Update documentation
        Write-Log "Updating documentation for $packageName v$version..." -Level "INFO"
        $docUpdateSuccess = Update-ModuleDocumentation -ModulePath $packagePath -Table $releaseNotesTable -PackageName $packageName -Version $version

        if (-not $docUpdateSuccess)
        {
            Write-Log "Warning: Documentation update failed for $packageName v$version" -Level "WARNING"
            # Continue processing despite documentation issues
        }

        # Update telemetry settings
        Write-Log "Updating telemetry settings for $packageName v$version..." -Level "INFO"

        @(
            @{
                Action         = { Update-TelemetryDefault -Path $packagePath }
                SuccessMessage = "Successfully updated telemetry settings"
                WarningMessage = "Failed to update telemetry settings"
            },
            @{
                Action            = { Update-TelemetryDefaultInMarkdown -Path $packagePath }
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
        Add-DisclaimerFile -PackageName $packageName -Path $packagePath

        if ($testSuccess)
        {
            # Update state to Tested
            Update-PackageVersionState -Table $table -PackageName $packageName -Version $version -Status "Tested"
            $testedCount++
            Write-Log "Successfully tested $packageName v$version" -Level "SUCCESS"
        }
        else
        {
            # Update state to Failed
            Update-PackageVersionState -Table $table -PackageName $packageName -Version $version -Status "Failed" -ErrorMessage "Terraform validation failed"
            $failedCount++
            $failedPackages += "$packageName v$version"
            Write-Log "Failed testing $packageName v$version" -Level "ERROR"
        }
    }

    # Send report to Teams if we have any results to report
    # if ($testedCount -gt 0 -or $failedCount -gt 0)
    # {
    #     $reportMessage = "Package testing completed with the following results:`n`n"
    #     $reportMessage += "- Successfully tested: $testedCount packages/versions`n"
    #     $reportMessage += "- Failed: $failedCount packages/versions`n"

    #     if ($failedCount -gt 0)
    #     {
    #         $reportMessage += "`nFailed packages:`n"
    #         foreach ($failedPackage in $failedPackages)
    #         {
    #             $reportMessage += "- $failedPackage`n"
    #         }
    #     }

    #     if (-not [string]::IsNullOrWhiteSpace($reportMessage) -and -not [string]::IsNullOrWhiteSpace($TeamsWebhookUrl))
    #     {
    #         Send-TeamsNotification -Message $reportMessage -WebhookUrl $TeamsWebhookUrl -Color $(if ($failedCount -gt 0) { "FF0000" } else { "00FF00" })
    #     }
    # }

    # Log final status
    if ($failedCount -gt 0)
    {
        Write-Log "Testing process completed. Successful: $testedCount, Failed: $failedCount" -Level "WARNING"
    }
    else
    {
        Write-Log "Testing process completed. Successful: $testedCount, Failed: $failedCount" -Level "SUCCESS"
    }
}
catch
{
    Write-Log "Critical error in testing execution:" -Level "ERROR"
    Write-Log "Error Message: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Error Details: $($_)" -Level "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level "ERROR"

    if (-not [string]::IsNullOrWhiteSpace($TeamsWebhookUrl) -and -not [string]::IsNullOrWhiteSpace($_.Exception.Message))
    {
        Send-TeamsNotification -Message "Critical error in AVM package testing process:`n$($_.Exception.Message)" -WebhookUrl $TeamsWebhookUrl -Title "AVM Testing Error" -Color "FF0000"
    }
    exit 1
}
