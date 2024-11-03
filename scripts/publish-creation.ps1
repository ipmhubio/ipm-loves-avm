[CmdletBinding()]
Param(
  [Parameter(Mandatory = $True)]
  [String] $AvmPackageBuildRoot,

  [Parameter(Mandatory = $True)]
  [String] $PackageCreationApi
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "avm-to-ipm-module.psm1") -Force

# 01. Get information from the build folder
$PackagesWithinBuildFolder = Get-ChildItem -Path $AvmPackageBuildRoot -Directory
"Found {0} packages within the build folder." -f $PackagesWithinBuildFolder.Count | Write-Host

$BuildResults = Get-Content -Path (Join-Path -Path $AvmPackageBuildRoot -ChildPath "results.json") -Encoding "UTF8" | ConvertFrom-Json -Depth 100
$Modules = $BuildResults.Modules | ForEach-Object { [PsCustomObject] @{ Name = $_.IpmHubName; Description = $_.Description }}

"Ensuring that all packages exists within IPMHub..." | Write-Host
$Res = Invoke-IpmHubPackageEnsurance -Packages $Modules -PackageCreationApi $PackageCreationApi -Verbose:$VerbosePreference
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
# TODO - Publish new versions through ipm

# Save information about the total number of created packages and total number of uploaded packages
If ($env:GITHUB_ENV)
{
  $TotalPackageVersionsPublished = 0
  $DataToExport = @"
TOTAL_PACKAGES_CREATED={0}
TOTAL_PACKAGES_ALREADY_EXISTED={1}
TOTAL_PACKAGES_FAILED={2}
TOTAL_PACKAGEVERSIONS_PUBLISHED={3}
"@ -f $TotalPackagesCreated, $TotalPackagesAlreadyExists, $TotalPackagesFailed, $TotalPackageVersionsPublished
  $DataToExport | Out-File -FilePath $env:GITHUB_ENV -Encoding "UTF8"

  Write-Output "::set-output name=TOTAL_PACKAGES_CREATED::$TotalPackagesCreated"
  Write-Output "::set-output name=TOTAL_PACKAGES_ALREADY_EXISTED::$TotalPackagesAlreadyExists"
  Write-Output "::set-output name=TOTAL_PACKAGES_FAILED::$TotalPackagesFailed"
  Write-Output "::set-output name=TOTAL_PACKAGEVERSIONS_PUBLISHED::$TotalPackageVersionsPublished"
}