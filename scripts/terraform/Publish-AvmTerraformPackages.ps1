

<#
.SYNOPSIS
    Publishes tested Azure Verified Modules (AVM) Terraform packages to IPM.
.DESCRIPTION
    This script identifies packages in the Tested state and publishes them to IPM,
    updating their status to Published or Failed accordingly.
.PARAMETER StorageAccountName
    Azure Storage Account Name for state management.
.PARAMETER StorageAccountKey
    Azure Storage Account Key for state management.
.PARAMETER TableName
    Azure Storage Table Name for state management.
.PARAMETER StagingDirectory
    Directory where packages are downloaded and processed.
.PARAMETER IpmClientPath
    Path to the IPM client executable.
.PARAMETER ipmOrganization
    IPM organization name.
.PARAMETER TeamsWebhookUrl
    Microsoft Teams webhook URL for status reporting.
.PARAMETER UseAzurite
    Boolean flag to indicate if Azurite should be used for local development.
#>

[CmdletBinding()]
param (

    [Parameter(Mandatory = $false)]
    [string]$logicAppUrl,

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName = "devstoreaccount1",

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountKey = "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==",

    [Parameter(Mandatory = $false)]
    [string]$StorageSasToken,

    [Parameter(Mandatory = $false)]
    [string]$TableName = "AvmPackageVersions",

    [Parameter(Mandatory = $false)]
    [string]$StagingDirectory = "staging",

    [Parameter(Mandatory = $false)]
    [string]$ipmOrganization = "avm-terraform",

    [Parameter(Mandatory = $false)]
    [string]$TeamsWebhookUrl,

    [Parameter(Mandatory = $false)]
    [bool]$UseAzurite = $true,

    [Parameter(Mandatory = $false)]
    [bool]$LocalRun = $false
)

# Import required modules and types
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "avm-tf-to-ipm-module/avm-tf-to-ipm-module.psm1") -Force

# Install and import required Azure Table Storage module
if (-not (Get-Module -ListAvailable -Name AzTable))
{
    Install-Module -Name AzTable -Force -AllowClobber -Scope CurrentUser
}
Import-Module AzTable

#region Main Execution
$ErrorActionPreference = "Stop"
$publishedCount = 0
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

    # Get all packages that are in Tested state from the table
    $packagesToPublish = Get-TableEntities -Table $table | Where-Object { $_.Status -eq "Tested" }

    Write-Log "Found $($packagesToPublish.Count) packages to publish" -Level "INFO"

    #for each package create a distinct package name
    $distinctPackages = $packagesToPublish | Where-Object { $_.Status -eq "Tested" -or $_.Status -eq "Published-tested" -and $_.PartitionKey -ne $null -and $_.PartitionKey -ne "" } | Select-Object -Property PartitionKey -Unique

    write-Log "Found $($distinctPackages.Count) distinct packages to publish" -Level "INFO"
    write-log "Distinct packages: $($distinctPackages | Out-String)" -Level "DEBUG"

    $newPackages = @(
        foreach ($package in $distinctPackages)
        {
            $IPMPackageName = New-IpmPackageName -TerraformName $package.PartitionKey
            @{
                Name     = $IPMPackageName
                description     = "This Terraform Azure Verified Module deploys: $($package.PartitionKey)"
                descriptionLang = "EN"
                projectUri      = "https://ipmhub.io/avm-terraform"
            }
        }
    )



    Write-Log "Creating $($newPackages.Count) new packages in IPMHub" -Level "INFO"
    Write-Log "New packages: $($newPackages | Out-String)" -Level "DEBUG"
    # Convert string "1" to boolean using simple comparison
    $isLocalRun = $LocalRun
    Write-Log "local run is set to: $($isLocalRun)" -level "DEBUG"

    $packageEnsuranceResult = Invoke-IpmHubPackageEnsurance `
        -Packages $newPackages `
        -PackageCreationApi $logicAppUrl `
        -LocalRun $LocalRun

    # Report on package creation results
    if ($packageEnsuranceResult.Failed -gt 0)
    {
        Write-Log "WARNING: Some packages failed to be registered in IPMHub" -Level "WARNING"
        Write-Log "Failed packages:" -Level "WARNING"
        foreach ($failedPkg in $packageEnsuranceResult.FailedPackages)
        {
            Write-Log "  - $($failedPkg.packageName) (Status code: $($failedPkg.statusCode))" -Level "WARNING"
        }
    }

    # Report on successful packages (limited to 10)
    if ($packageEnsuranceResult.Successful -gt 0)
    {
        Write-Log "Successfully registered packages in IPMHub:" -Level "INFO"
        foreach ($successPkg in $packageEnsuranceResult.SuccessfulPackages)
        {
            Write-Log "  - $($successPkg.packageName) (latest version: $($successPkg.latestVersion))" -Level "INFO"
        }

        if ($packageEnsuranceResult.Successful -gt 10)
        {
            Write-Log "  ...and $($packageEnsuranceResult.Successful - 10) more packages" -Level "INFO"
        }
    }

    # Report on new vs updated packages
    if ($packageEnsuranceResult.New -gt 0)
    {
        Write-Log "Created $($packageEnsuranceResult.New) new packages in IPMHub" -Level "INFO"
    }

    if ($packageEnsuranceResult.Updated -gt 0)
    {
        Write-Log "Updated $($packageEnsuranceResult.Updated) existing packages in IPMHub" -Level "INFO"
    }

    foreach ($packageEntity in $packagesToPublish)
    {
        $packageName = $packageEntity.PartitionKey
        $version = $packageEntity.RowKey

        Write-Log "Publishing package: $packageName version: $version" -Level "INFO"

        # Update state to Publishing
        Update-PackageVersionState -Table $table -PackageName $packageName -Version $version -Status "Publishing"

        # Locate the build-for-ipm folder for this package
        $versionPath = $version -replace '-', '.'
        $packagePath = Join-Path -Path $StagingDirectory -ChildPath "$packageName/$versionPath/build-for-ipm"

        if (-not (Test-Path $packagePath))
        {
            Write-Log "Package path does not exist: $packagePath" -Level "ERROR"
            Update-PackageVersionState -Table $table -PackageName $packageName -Version $version -Status "Failed" -ErrorMessage "Package path not found"
            $failedCount++
            $failedPackages += "$packageName v$version"
            continue
        }

        # Check if running locally
        $isLocalRun = $LocalRun
        Write-Log "Publishing with LocalRun set to: $isLocalRun" -Level "DEBUG"

        # Publish to IPM
        $publishResult = Publish-ToIpm `
            -PackagePath $packagePath `
            -PackageName $packageName `
            -ipmOrganization $ipmOrganization `
            -Version $version `
            -LocalRun $isLocalRun

        if ($publishResult.Success -eq $true)
        {
            # Update state to Published
            Update-PackageVersionState -Table $table -PackageName $packageName -Version $version -Status "Published-tested" -ErrorMessage $null
            $publishedCount++
            Write-Log "Successfully published $packageName v$version" -Level "SUCCESS"
        }
        else
        {
            # Update state to Failed
            Update-PackageVersionState -Table $table -PackageName $packageName -Version $version -Status "Failed" -ErrorMessage "Failed to publish: $($publishResult.Message)"
            $failedCount++
            $failedPackages += "$packageName v$version"
            Write-Log "Failed to publish $packageName v$version : $($publishResult.Message)" -Level "ERROR"
        }
    }


    if ($failedCount -gt 0)
    {
        Write-Log "Publishing process completed. Successful: $publishedCount, Failed: $failedCount" -Level "WARNING"
    }
    else
    {
        Write-Log "Publishing process completed. Successful: $publishedCount, Failed: $failedCount" -Level "SUCCESS"
    }

    # Generate and display complete process summary
    Write-Log "===== AVM TERRAFORM PACKAGE PROCESSING SUMMARY =====" -Level "INFO"

    # Package Registration Summary
    Write-Log "PACKAGE REGISTRATION:" -Level "INFO"
    Write-Log "  Total Packages Processed: $($packageEnsuranceResult.TotalProcessed)" -Level "INFO"
    Write-Log "  Successfully Registered: $($packageEnsuranceResult.Successful)" -Level "INFO"
    Write-Log "  Failed Registration: $($packageEnsuranceResult.Failed)" -Level "INFO"
    Write-Log "  Newly Created Packages: $($packageEnsuranceResult.New)" -Level "INFO"
    Write-Log "  Updated Packages: $($packageEnsuranceResult.Updated)" -Level "INFO"

    # Package Publishing Summary
    Write-Log "PACKAGE VERSION PUBLISHING:" -Level "INFO"
    Write-Log "  Total Versions Processed: $($packagesToPublish.Count)" -Level "INFO"
    Write-Log "  Successfully Published: $publishedCount" -Level "INFO"
    Write-Log "  Failed to Publish: $failedCount" -Level "INFO"

    # Detailed Failed Package Information
    if ($failedCount -gt 0)
    {
        Write-Log "FAILED PACKAGE VERSIONS:" -Level "WARNING"
        foreach ($failedPackage in $failedPackages)
        {
            Write-Log "  - $failedPackage" -Level "WARNING"
        }
    }

    # Send summary to Teams if webhook URL is provided
    if (-not [string]::IsNullOrWhiteSpace($TeamsWebhookUrl))
    {
        $color = if ($failedCount -gt 0 -or $packageEnsuranceResult.Failed -gt 0) { "FFA500" } else { "00FF00" }
        $summaryMessage = @"
## AVM Terraform Package Processing Summary
### Package Registration:
- Total Processed: $($packageEnsuranceResult.TotalProcessed)
- Successfully Registered: $($packageEnsuranceResult.Successful)
- Failed Registration: $($packageEnsuranceResult.Failed)
- Newly Created: $($packageEnsuranceResult.New)
- Updated: $($packageEnsuranceResult.Updated)

### Package Version Publishing:
- Total Versions: $($packagesToPublish.Count)
- Successfully Published: $publishedCount
- Failed: $failedCount
"@

        if ($failedCount -gt 0)
        {
            $summaryMessage += "`n`n**Failed Package Versions:**`n"
            $summaryMessage += ($failedPackages | ForEach-Object { "- $_" }) -join "`n"
        }

        Send-TeamsNotification -Message $summaryMessage -WebhookUrl $TeamsWebhookUrl -Title "AVM Terraform Package Processing Report" -Color $color
    }

    Write-Log "=================================================" -Level "INFO"
}
catch
{
    Write-Log "Critical error in publishing execution:" -Level "ERROR"
    Write-Log "Error Message: $($_.Exception.Message)" -Level "ERROR"
    Write-Log "Error Details: $($_)" -Level "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level "ERROR"

    if (-not [string]::IsNullOrWhiteSpace($TeamsWebhookUrl) -and -not [string]::IsNullOrWhiteSpace($_.Exception.Message))
    {
        Send-TeamsNotification -Message "Critical error in AVM package publishing process:`n$($_.Exception.Message)" -WebhookUrl $TeamsWebhookUrl -Title "AVM Publishing Error" -Color "FF0000"
    }
    exit 1
}
