using namespace Microsoft.Azure.Cosmos.Table

<#
.SYNOPSIS
    Discovers and downloads Azure Verified Modules (AVM) Terraform packages.
.DESCRIPTION
    This script discovers new AVM Terraform modules by querying GitHub and comparing
    with previously processed versions. New packages are downloaded and prepared for testing.
.PARAMETER GithubToken
    GitHub Personal Access Token for API access.
.PARAMETER StorageAccountName
    Azure Storage Account Name for state management.
.PARAMETER StorageAccountKey
    Azure Storage Account Key for state management.
.PARAMETER TableName
    Azure Storage Table Name for state management.
.PARAMETER TableNameReleaseNotes
    Azure Storage Table Name for release notes.
.PARAMETER StagingDirectory
    Directory where packages will be downloaded and processed.
.PARAMETER ipmOrganization
    IPM organization name.
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
    [string]$StorageSasToken,

    [Parameter(Mandatory = $false)]
    [string]$TableName = "AvmPackageVersions",

    [Parameter(Mandatory = $false)]
    [string]$TableNameReleaseNotes = "AvmPackageReleaseNotes",

    [Parameter(Mandatory = $false)]
    [string]$StagingDirectory = "staging",

    [Parameter(Mandatory = $false)]
    [string]$ipmOrganization = "avm-tf",

    [Parameter(Mandatory = $false)]
    [string]$TeamsWebhookUrl,

    [Parameter(Mandatory = $false)]
    [bool]$UseAzurite = $true,

    [Parameter(Mandatory = $false)]
    [bool]$localrun = $false
)

# Import required modules and types
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "avm-to-ipm-module/avm-tf-to-ipm-module.psm1") -Force
# Check if the module is available
Get-Module -Name "avm-tf-to-ipm-module" -ErrorAction SilentlyContinue
#list all functuins in the module
$module = Get-Module -Name "avm-tf-to-ipm-module"
$module.Functions | ForEach-Object { $_.Name }
# Install and import required Azure Table Storage module
if (-not (Get-Module -ListAvailable -Name AzTable))
{
    Install-Module -Name AzTable -Force -AllowClobber -Scope CurrentUser
}


#region Main Execution
$ErrorActionPreference = "Stop"
$downloadedCount = 0
$failedCount = 0
$failedPackages = @()

try
{
    # Initialize Azure Storage Table with Azurite support
    $table = Initialize-AzureStorageTable `
        -StorageAccountName $StorageAccountName `
        -SasToken $StorageSasToken `
        -TableName $TableName `
        -UseAzurite $UseAzurite

    $releaseNotesTable = Initialize-AzureStorageTable `
        -StorageAccountName $StorageAccountName `
        -SasToken $StorageSasToken `
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
    $searchUrl = "https://api.github.com/search/repositories?q=org:azure+terraform-azurerm-avm-res-+in:name&per_page=100"
    $allRepoItems = @()
    $page = 1

    do
    {
        $pageUrl = "$searchUrl&page=$page"
        Write-Log "Searching for AVM repositories (page $page)..." -Level "INFO"
        $repos = Invoke-RestMethod -Uri $pageUrl -Headers $headers -Method Get
        $allRepoItems += $repos.items

        # Check if there are more pages
        $hasMorePages = $repos.items.Count -eq 100
        $page++
    } while ($hasMorePages)

    Write-Log "Found total of $($allRepoItems.Count) repositories" -Level "INFO"

    # Process each repository to download new packages
    foreach ($repo in $allRepoItems)
    {
        $repoName = $repo.name
        Write-Log "Processing repository: $repoName" -Level "INFO"
        Write-log "check if $repoName is already in table" -Level "INFO"

        # Get releases for this repository
        $releasesUrl = "https://api.github.com/repos/Azure/$repoName/releases"
        $releases = Invoke-RestMethod -Uri $releasesUrl -Headers $headers -Method Get
        $releases = $releases | Sort-Object -Property created_at

        foreach ($release in $releases)
        {
            Write-Log "Processing Package: $repoName Version: $($release.tag_name)" -Level "INFO"
            $version = if ($release.tag_name.StartsWith('v'))
            {
                $release.tag_name.Substring(1)
            }
            else
            {
                $release.tag_name
            }

            # Check if this version is already processed
            Write-Log "Starting Get-PackageVersionState for package '$repoName' version '$version'" -Level "INFO"
            $existingState = Get-PackageVersionState -Table $table -PackageName $repoName -Version $version
            Write-Log "Current state $existingState" -Level "DEBUG"

            # Skip processing if already processed
            if ($existingState -and ($existingState -eq "Failed" -or $existingState -eq "Published" -or $existingState -eq "Published-tested"))
            {
                Write-Log "Package $repoName version $version is already in state: $existingState. Skipping." -Level "INFO"
                continue
            }

            # Update state to Downloading
            Update-PackageVersionState -Table $table -PackageName $repoName -Version $version -Status "Downloading" -published $release.published_at

            # Update release notes before processing
            write-log "Updating release notes for $repoName version $version" -Level "INFO"
            Update-ReleaseNotes `
                -table $releaseNotesTable `
                -PackageName $repoName `
                -Version $version `
                -ReleaseNotes $release.body `
                -CreatedAt $release.created_at

            # Download and extract the package
            $moduleResult = Get-AvmTerraformModule -PackageName $repoName -Version $version -TarballUrl $release.tarball_url `
                -StagingDirectory $StagingDirectory -GithubToken $GithubToken

            if ($moduleResult.Success)
            {
                # Create build-for-ipm folder and copy files
                $extractedPath = $moduleResult.ModulePath
                $versionFolderPath = Split-Path $extractedPath -Parent
                Copy-ExtractedToIpmBuild -ExtractedPath $extractedPath -VersionFolderPath $versionFolderPath

                # Update state to Downloaded
                Update-PackageVersionState -Table $table -PackageName $repoName -Version $version -Status "Downloaded"
                $downloadedCount++
            }
            else
            {
                Write-Log "Failed to download $repoName version $version : $($moduleResult.Message)" -Level "ERROR"
                Update-PackageVersionState -Table $table -PackageName $repoName -Version $version -Status "Failed" -ErrorMessage $moduleResult.Message
                $failedCount++
                $failedPackages += "$repoName v$version"
            }
        }
    }

    # Send report to Teams if we have any results to report
    if ($downloadedCount -gt 0 -or $failedCount -gt 0)
    {
        $reportMessage = "Package discovery and download completed with the following results:`n`n"
        $reportMessage += "- Successfully downloaded: $downloadedCount packages/versions`n"
        $reportMessage += "- Failed: $failedCount packages/versions`n"

        if ($failedCount -gt 0)
        {
            $reportMessage += "`nFailed packages:`n"
            foreach ($failedPackage in $failedPackages)
            {
                $reportMessage += "- $failedPackage`n"
            }
        }

    }

    # Log final status
    if ($failedCount -gt 0)
    {
        Write-Log "Download process completed. Successful: $downloadedCount, Failed: $failedCount" -Level "WARNING"
        Write-Log "Failed packages: $($failedPackages -join ', ')" -Level "WARNING"
    }
    else
    {
        Write-Log "Download process completed. Successful: $downloadedCount, Failed: $failedCount" -Level "SUCCESS"
        write-log "reportMessage: $reportMessage" -Level "INFO"
    }
}
catch
{
    Write-Log "Critical error in download execution:" -Level "ERROR"
    Write-Log "Error Message: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Error Details: $($_)" -Level "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level "ERROR"

    if (-not [string]::IsNullOrWhiteSpace($TeamsWebhookUrl) -and -not [string]::IsNullOrWhiteSpace($_.Exception.Message))
    {
        Send-TeamsNotification -Message "Critical error in AVM package download process:`n$($_.Exception.Message)" -WebhookUrl $TeamsWebhookUrl -Title "AVM Download Error" -Color "FF0000"
    }
    exit 1
}
