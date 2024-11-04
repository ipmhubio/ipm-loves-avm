[CmdletBinding()]
Param(
  [Parameter(Mandatory = $True)]
  [String] $AvmPackageBuildRoot,

  [Parameter(Mandatory = $True)]
  [String] $PackageCreationApi
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "avm-to-ipm-module.psm1") -Force

# 01. Get information from the build folder
$AvmBuildPublishSet = Get-AvmBuildPublishSet -AvmPackageBuildRoot $AvmPackageBuildRoot
"Found {0} unique packages within the build folder, with a total of {1} versions." -f $AvmBuildPublishSet.UniquePackages.Count, $AvmBuildPublishSet.Packages.Count | Write-Host

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

"Publishing new versions..." | Write-Host
ForEach($Package in $AvmBuildPublishSet.Packages)
{
  "ipm publish -p `"{0}`" -v `"{1}`" -f `"{2}`"" -f $Package.Name, $Package.Version, $Package.Path | Write-Host
}

# Save information about the total number of created packages and total number of uploaded packages
If ($env:GITHUB_ENV)
{
  $TotalPackageVersionsPublished = $AvmBuildPublishSet.Packages.Count
  $DataToExport = @"
TOTAL_PACKAGES_CREATED={0}
TOTAL_PACKAGES_ALREADY_EXISTED={1}
TOTAL_PACKAGES_FAILED={2}
TOTAL_PACKAGEVERSIONS_PUBLISHED={3}
"@ -f $TotalPackagesCreated, $TotalPackagesAlreadyExists, $TotalPackagesFailed, $TotalPackageVersionsPublished
  $DataToExport | Out-File -FilePath $env:GITHUB_ENV -Encoding "UTF8"

  # Write outputs to GITHUB_OUTPUT (for use in other jobs)
  $DataToExport | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding "UTF8"
}