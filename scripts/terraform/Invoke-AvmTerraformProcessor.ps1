using namespace Microsoft.Azure.Cosmos.Table

<#
.SYNOPSIS
    Processes Azure Verified Modules (AVM) Terraform packages and republishes them to IPM.
.DESCRIPTION
    This script orchestrates the entire workflow for finding, downloading, processing, and publishing
    AVM Terraform modules to your internal platform. It handles state management between runs and
    ensures that failed packages are retried in subsequent runs.
.PARAMETER GithubToken
    GitHub Personal Access Token for API access.
.PARAMETER StorageAccountName
    Azure Storage Account Name for state management.
.PARAMETER StorageAccountKey
    Azure Storage Account Key for state management.
.PARAMETER TableName
    Azure Storage Table Name for state management.
.PARAMETER StagingDirectory
    Directory where packages will be downloaded and processed.
.PARAMETER IpmClientPath
    Path to the IPM client executable.
.PARAMETER TeamsWebhookUrl
    Microsoft Teams webhook URL for status reporting.
.PARAMETER UseAzurite
    Boolean flag to indicate if Azurite should be used for local development.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$GithubToken,

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName = "devstoreaccount1",

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountKey = "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==",

    [Parameter(Mandatory = $false)]
    [string]$TableName = "AvmPackageVersions",

    [Parameter(Mandatory = $false)]
    [string]$TableNameReleaseNotes = "AvmPackageReleaseNotes",

    [Parameter(Mandatory = $false)]
    [string]$StagingDirectory = "staging",

    [Parameter(Mandatory = $false)]
    [string]$IpmClientPath = "ipm",

    [Parameter(Mandatory = $false)]
    [string]$TeamsWebhookUrl,

    [Parameter(Mandatory = $false)]
    [bool]$UseAzurite = $true
)

# Import required modules and types
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "avm-to-ipm-module/avm-tf-to-ipm-module.psm1") -Force

# Install and import required Azure Table Storage module
if (-not (Get-Module -ListAvailable -Name AzTable))
{
    Install-Module -Name AzTable -Force -AllowClobber -Scope CurrentUser
}
Import-Module AzTable

#region Main Execution
$ErrorActionPreference = "Stop"
$processedCount = 0
$failedCount = 0
$failedPackages = @()

try
{
    # Initialize Azure Storage Table with Azurite support
    $table = Initialize-AzureStorageTable `
        -StorageAccountName $StorageAccountName `
        -StorageAccountKey $StorageAccountKey `
        -TableName $TableName `
        -UseAzurite $UseAzurite

    $releaseNotesTable = Initialize-AzureStorageTable `
        -StorageAccountName $StorageAccountName `
        -StorageAccountKey $StorageAccountKey `
        -TableName $TableNameReleaseNotes `
        -UseAzurite $UseAzurite

    # Initialize environment
    Initialize-Environment -StagingDirectory $StagingDirectory

    # Get repos and releases directly from GitHub API
    $headers = @{
        'Accept'        = 'application/vnd.github+json'
        'Authorization' = "Bearer $GithubToken"
    }

    # Search for AVM repos
    $searchUrl = "https://api.github.com/search/repositories?q=org:azure+terraform-azurerm-avm-res-storage+in:name&per_page=100"
    Write-Log "Searching for AVM repositories..." -Level "INFO"
    $repos = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method Get
    Write-Information $repos
    $repoItems = $repos.items

    foreach ($repo in $repoItems)
    {
        $repoName = $repo.name
        Write-Log "Processing repository: $repoName" -Level "INFO"

        # Get releases for this repository
        $releasesUrl = "https://api.github.com/repos/Azure/$repoName/releases"
        $releases = Invoke-RestMethod -Uri $releasesUrl -Headers $headers -Method Get
        $releases = $releases | Sort-Object -Property created_at



        foreach ($release in $releases)
        {
            Write-Log "Processing Package: $repoName Version: $($release.tag_name)" -Level "INFO"
            Write-log "Total releases: $($releases.Count)" -Level "DEBUG"
            $version = if ($release.tag_name.StartsWith('v'))
            {
                $release.tag_name.Substring(1)
            }
            else
            {
                $release.tag_name
            }

            # Check if this version is already processed and published successfully
            Write-Log "Starting Get-PackageVersionState for package '$repoName' version '$version'" -Level "INFO"
            $existingState = Get-PackageVersionState -Table $table -PackageName $repoName -Version $version

            if ($existingState -eq "Published")
            {
                write-log "Found existing state for $repoName version $version : $existingState.Status" -Level "DEBUG"
                Write-Log ("Found existing state for {0} version {1}: {2}" -f $repoName, $version, $existingState.Status) -Level "DEBUG"
                if ($existingState.Success)
                {
                    Write-Log "Package $repoName version $version is already published successfully. Skipping." -Level "INFO"
                    # Return result hashtable with Done = true for published packages
                    continue
                }
                elseif ($existingState.Status -eq "Failed")
                {
                    Write-Log "Package $repoName version $version previously failed. Retrying..." -Level "WARNING"
                }
            }

            # Only proceed with processing if not already published
            Write-Log "Processing $repoName version $version..." -Level "INFO"
            # Update state to Processing
            Update-PackageVersionState -Table $table -PackageName $repoName -Version $version -Status "Processing"

            # Update release notes before processing
            write-log "Updating release notes for $repoName version $version" -Level "INFO"
            Update-ReleaseNotes `
                -table $releaseNotesTable `
                -PackageName $repoName `
                -Version $version `
                -ReleaseNotes $release.body `
                -CreatedAt $release.created_at

            $result = Invoke-AvmRelease -Package @{
                name = $repoName
                url  = $repo.html_url
            } -Release @{
                version      = $version
                published_at = $release.published_at
                tarball_url  = $release.tarball_url
            } -StagingRoot $StagingDirectory -GithubToken $GithubToken

            if ($result.Success)
            {
                Update-PackageVersionState -Table $table -PackageName $repoName -Version $version -Status "Published"
                $processedCount++
            }
            else
            {
                Update-PackageVersionState -Table $table -PackageName $repoName -Version $version -Status "Failed" -ErrorMessage $result.Message
                $failedCount++
                $failedPackages += "$repoName v$version"
            }

            if ($result.Done)
            {
                Write-Log "Package $repoName version $version is marked as done. Moving to next version." -Level "INFO"
                continue
            }

            # Add a small delay to avoid rate limiting
            Start-Sleep -Milliseconds 500
        }
    }

    # Send report to Teams if we have any results to report
    if ($processedCount -gt 0 -or $failedCount -gt 0)
    {
        $reportMessage = "Processing completed with the following results:`n`n"
        $reportMessage += "- Successfully processed: $processedCount packages/versions`n"
        $reportMessage += "- Failed: $failedCount packages/versions`n"

        if ($failedCount -gt 0)
        {
            $reportMessage += "`nFailed packages:`n"
            foreach ($failedPackage in $failedPackages)
            {
                $reportMessage += "- $failedPackage`n"
            }
        }

        Send-TeamsNotification -Message $reportMessage -Color $(if ($failedCount -gt 0) { "FF0000" } else { "00FF00" })
    }

    # Log final status
    if ($failedCount -gt 0)
    {
        Write-Log "Processing completed. Successful: $processedCount, Failed: $failedCount" -Level "WARNING"
    }
    else
    {
        Write-Log "Processing completed. Successful: $processedCount, Failed: $failedCount" -Level "SUCCESS"
    }
}
catch
{
    Write-Log "Critical error in main execution: $_" -Level "ERROR"
    Send-TeamsNotification -Message "Critical error in AVM package processing: $_" -Title "AVM Processing Error" -Color "FF0000"
    exit 1
}