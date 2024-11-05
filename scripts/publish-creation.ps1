[CmdletBinding()]
Param(
  [Parameter(Mandatory = $True)]
  [String] $AvmPackageBuildRoot,

  [Parameter(Mandatory = $True)]
  [String] $PackageCreationApi
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "avm-to-ipm-module.psm1") -Force

# 01. Get information from the build folder.
$AvmBuildPublishSet = Get-AvmBuildPublishSet -AvmPackageBuildRoot $AvmPackageBuildRoot
"Found {0} unique packages within the build folder, with a total of {1} versions." -f $AvmBuildPublishSet.UniquePackages.Count, $AvmBuildPublishSet.Packages.Count | Write-Host

# 02. Ensure that all packages exist within the hub.
"Ensuring that all packages exists within IPMHub..." | Write-Host
$Res = Invoke-IpmHubPackageEnsurance -Packages $AvmBuildPublishSet.UniquePackages -PackageCreationApi $PackageCreationApi -Verbose:$VerbosePreference
$PackagesCreated = [Array] ($Res | Where-Object { $_.statusCode -eq 201 }) ?? @()
$PackagesExists = [Array] ($Res | Where-Object { $_.statusCode -eq 200 }) ?? @()
$PackagesFailed = [Array] ($Res | Where-Object { $_.statusCode -ge 400 }) ?? @()
$TotalPackagesCreated = $PackagesCreated.Count
$TotalPackagesAlreadyExists = $PackagesExists.Count
$TotalPackagesFailed = $PackagesFailed.Count

If ($TotalPackagesFailed -eq 0)
{
  "A total of {0} packages were created, {1} already existed and {2} failed." -f $TotalPackagesCreated, $TotalPackagesAlreadyExists, $TotalPackagesFailed | Write-Host
} `
Else
{
  Throw ("A total of {0} packages were created, {1} already existed and {2} failed." -f $TotalPackagesCreated, $TotalPackagesAlreadyExists, $TotalPackagesFailed)
}

# 03. Use IPM to publish new versions.
"Publishing new versions..." | Write-Host
$FailedPublications = @()
ForEach($Package in $AvmBuildPublishSet.Packages)
{
  $PackageHubInfo = $Res | Where-Object { $_.packageName -eq $Package.FullName } | Select-Object -First 1
  $PackageHubVersions = [Array] ($PackageHubInfo.versions) ?? @()
  If ($PackageHubVersions -contains $Package.Version)
  {
    "Package '{0}' version '{1}' already exists within IPMHub. Skipping." -f $Package.Name, $Package.Version | Write-Warning
    Continue
  }

  "Publishing package '{0}' version '{1}'..." -f $Package.Name, $Package.Version | Write-Host
  Try
  {
    & ipm publish -p "avm-bicep/$($Package.Name)" -v "$($Package.Version)" -f "$($Package.Path)" --with-custom-authorization
  }
  Catch
  {
    "Package '{0}' version '{1}' publication failed due reason: {2}" -f $_.ToString() | Write-Warning
    $FailedPublications += $Package
  }
}

# 04. Save information about the total number of created packages and total number of uploaded packages.
If ($env:GITHUB_ENV)
{
  $TotalPackageVersionsPublished = $AvmBuildPublishSet.Packages.Count
  $DataToExport = @"
TOTAL_PACKAGES_CREATED={0}
TOTAL_PACKAGES_ALREADY_EXISTED={1}
TOTAL_PACKAGES_FAILED={2}
TOTAL_PACKAGEVERSIONS_PUBLISHED={3}
TOTAL_PACKAGEVERSIONS_FAILED={4}
"@ -f $TotalPackagesCreated, $TotalPackagesAlreadyExists, $TotalPackagesFailed, $TotalPackageVersionsPublished, $FailedPublications.Count
  $DataToExport | Out-File -FilePath $env:GITHUB_ENV -Encoding "UTF8"

  # Write outputs to GITHUB_OUTPUT (for use in other jobs)
  $DataToExport | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding "UTF8"
}