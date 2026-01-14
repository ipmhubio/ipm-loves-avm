[CmdletBinding()]
Param(
  [Parameter(Mandatory = $True)]
  [String] $AvmPackageBuildRoot,

  [Parameter(Mandatory = $True)]
  [String] $PackageCreationApi
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath "avm-to-ipm-module.psm1") -Force

# 01. Get information from the build folder.
"Retrieving AVM build/publish set..." | Write-Host
$AvmBuildPublishSet = Get-AvmBuildPublishSet -AvmPackageBuildRoot $AvmPackageBuildRoot
"Found {0} unique packages within the build folder, with a total of {1} versions." -f $AvmBuildPublishSet.UniquePackages.Count, $AvmBuildPublishSet.Packages.Count | Write-Host

# 02. Ensure that all packages exist within the hub.
"Ensuring that all packages exists within IPMHub..." | Write-Host

# An Azure Logic App has a maximum runtime ~ 2 minuten.
# So if we have too many packagedata, we should break it up into chunks of 50.
$Res = @()
$ChunkSize = 50
$UniquePackages = $AvmBuildPublishSet.UniquePackages

If ($null -eq $UniquePackages -or $UniquePackages.Count -eq 0)
{
  $Res = @()
} `
ElseIf ($UniquePackages.Count -gt $ChunkSize)
{
  for ($Index = 0; $Index -lt $UniquePackages.Count; $Index += $ChunkSize)
  {
    $Take = [Math]::Min($ChunkSize, $UniquePackages.Count - $Index)
    $Chunk = @($UniquePackages[$Index..($Index + $Take - 1)])

    Write-Verbose ("Calling Invoke-IpmHubPackageEnsurance for chunk {0}-{1} of {2} (size: {3})" -f ($Index + 1), ($Index + $Take), $UniquePackages.Count, $Chunk.Count)

    $ChunkRes = Invoke-IpmHubPackageEnsurance -Packages $Chunk -PackageCreationApi $PackageCreationApi -Verbose:$VerbosePreference
    if ($null -ne $ChunkRes)
    {
      # Ensure array semantics even when a single object is returned
      $Res += @($ChunkRes)
    }
  }
} `
Else
{
  $Res = Invoke-IpmHubPackageEnsurance -Packages $AvmBuildPublishSet.UniquePackages -PackageCreationApi $PackageCreationApi -Verbose:$VerbosePreference
}

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
$TotalPackageVersionsPublished = 0
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
    If ($LASTEXITCODE -lt 0)
    {
      Throw ("Publication failed with exit code {0}" -f $LASTEXITCODE)
    } `
    Else
    {
      $TotalPackageVersionsPublished += 1
    }
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