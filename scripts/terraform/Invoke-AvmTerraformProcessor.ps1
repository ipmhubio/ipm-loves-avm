<#
.SYNOPSIS
    Processes Azure Verified Modules (AVM) Terraform packages and republishes them to IPM.
.DESCRIPTION
    This script orchestrates the entire workflow for finding, downloading, processing, and publishing
    AVM Terraform modules to your internal platform. It handles state management between runs and
    ensures that failed packages are retried in subsequent runs.
.PARAMETER GithubToken
    GitHub Personal Access Token for API access.
.PARAMETER StateFilePath
    Path to store the state file containing processed packages.
.PARAMETER StagingDirectory
    Directory where packages will be downloaded and processed.
.PARAMETER IpmClientPath
    Path to the IPM client executable.
.PARAMETER TeamsWebhookUrl
    Microsoft Teams webhook URL for status reporting.
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$GithubToken,

    [Parameter(Mandatory = $false)]
    [string]$StateFilePath = "azure-terraform-avm-releases.json",

    [Parameter(Mandatory = $false)]
    [string]$StagingDirectory = "staging",

    [Parameter(Mandatory = $false)]
    [string]$IpmClientPath = "ipm",

    [Parameter(Mandatory = $false)]
    [string]$TeamsWebhookUrl
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "avm-tf-to-ipm-module.psm1") -Force
#region Main Execution

$ErrorActionPreference = "Stop"
$processedCount = 0
$failedCount = 0
$failedPackages = @()

try {
    # Initialize environment
    Initialize-Environment -StagingDirectory $StagingDirectory -StateFilePath $StateFilePath

    # Get AVM releases from GitHub
    $newReleasesPath = Get-AzureAvmReleases -GithubToken $GithubToken -OutputPath (Join-Path -Path $PSScriptRoot -ChildPath $StateFilePath)

    # Compare with current state to find new releases
    $diffPath = Get-NewReleases -NewReleasesPath $newReleasesPath -CurrentStatePath "azure-terraform-avm-releases-new.json" -GithubToken $GithubToken

    if ([string]::IsNullOrEmpty($diffPath) -or -not (Test-Path -Path $diffPath)) {
        Write-Log "No new packages or releases found. Exiting." -Level "INFO"
        exit 0
    }

    # Process new releases
    Write-Log -Message "Processing new releases..." -Level "INFO"
    $diffContent = Get-Content -Path $diffPath -Raw | ConvertFrom-Json

    foreach ($package in $diffContent) {
        foreach ($release in $package.releases) {
            #$result = Invoke-AvmRelease -Package $package -Release $release -StagingRoot $StagingDirectory -GithubToken $GithubToken
            Write-Log "Publishing $packageName v$version to IPM..." -Level "INFO"

            #$publishSuccess = Publish-ToIpm -PackagePath $moduleDir -PackageName $packageName -Version $version
            $publishSuccess = $true # Temporary fix - replace with actual publishing code

            if (-not $publishSuccess) {
                Write-Log "Failed to publish $packageName v$version to IPM" -Level "ERROR"
                return $false
            }

            Write-Log "Successfully processed $packageName v$version" -Level "SUCCESS"
            return $true
            if ($result) {
                $processedCount++
            }
            else {
                $failedCount++
                $failedPackages += "$($package.name) v$($release.version)"
            }
        }
    }

    # Update state file with new releases if any were successful
    if ($processedCount -gt 0) {
        Write-Log "Updating state file with newly processed releases..." -Level "INFO"
        Copy-Item -Path $newReleasesPath -Destination $StateFilePath -Force
    }

    # Send report to Teams
    if ($processedCount -gt 0 -or $failedCount -gt 0) {
        $reportMessage = "Processing completed with the following results:`n`n"
        $reportMessage += "- Successfully processed: $processedCount packages/versions`n"
        $reportMessage += "- Failed: $failedCount packages/versions`n"

        if ($failedCount -gt 0) {
            $reportMessage += "`nFailed packages:`n"
            foreach ($failedPackage in $failedPackages) {
                $reportMessage += "- $failedPackage`n"
            }
        }

        Send-TeamsNotification -Message $reportMessage -Color $(if ($failedCount -gt 0) { "FF0000" } else { "00FF00" })
    }

    Write-Log "Processing completed. Successful: $processedCount, Failed: $failedCount" -Level $(if ($failedCount -gt 0) { "WARNING" } else { "SUCCESS" })
}
catch {
    Write-Log "Critical error in main execution: $_" -Level "ERROR"
    Send-TeamsNotification -Message "Critical error in AVM package processing: $_" -Title "AVM Processing Error" -Color "FF0000"
    exit 1
}

#endregion Main Execution