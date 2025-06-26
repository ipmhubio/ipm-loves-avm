[CmdletBinding()]
Param(
  [Parameter(Mandatory = $True)]
  [String] $AvmPackageBuildRoot,

  [Parameter(Mandatory = $True)]
  [String] $AvmPackagePublishRoot
)

$ScriptPath = $PSScriptRoot
If ([String]::IsNullOrEmpty($ScriptPath))
{
  $ScriptPath = $PSScriptRoot
}

Import-Module (Join-Path -Path $ScriptPath -ChildPath "avm-to-ipm-module.psm1") -Force

# 01a. Prepare our publish root path
If (-not (Test-Path -Path $AvmPackagePublishRoot -PathType "Container"))
{
  New-Item -Path $AvmPackagePublishRoot -ItemType "Directory" | Out-Null
}

# 01b. Make sure the test root path is empty.
Get-ChildItem -Path $AvmPackagePublishRoot | Remove-Item -Recurse -Force

# 02. Gather information about packages to build
$PackagesWithinBuildFolder = Get-ChildItem -Path $AvmPackageBuildRoot -Directory
"Found {0} packages within the build folder. Creating new builds per version..." -f $PackagesWithinBuildFolder.Count | Write-Host

$AvmBuildPublishSet = Get-AvmBuildPublishSet -AvmPackageBuildRoot $AvmPackageBuildRoot
"Found {0} unique packages within the build folder, with a total of {1} versions." -f $AvmBuildPublishSet.UniquePackages.Count, $AvmBuildPublishSet.Packages.Count | Write-Host

# 03. Build app packages with the IPM utility.
$FailedBuilds = @()
$TotalPackageVersionsBuild = 0
ForEach ($Package in $AvmBuildPublishSet.Packages)
{
  $PackageDestinationFolder = Join-Path -Path $AvmPackagePublishRoot -ChildPath $Package.Name -AdditionalChildPath $Package.Version
  $SummaryFile = Join-Path -Path $AvmPackagePublishRoot -ChildPath ("{0}_{1}-summary.json" -f $Package.Name, $Package.Version)
  If (-not (Test-Path -Path $PackageDestinationFolder -PathType "Container"))
  {
    New-Item -Path $PackageDestinationFolder -ItemType "Directory" | Out-Null
  }
  
  "Building package '{0}' version '{1}'..." -f $Package.Name, $Package.Version | Write-Host
  Try
  {
    & ipm build -s "$($Package.Path)" -d "$($PackageDestinationFolder)" --include-manifest --summary-file "$($SummaryFile)"
    If ($LASTEXITCODE -lt 0)
    {
      Throw ("Build failed with exit code {0}" -f $LASTEXITCODE)
    } `
    Else
    {
      $TotalPackageVersionsBuild += 1
    }
  }
  Catch
  {
    "Package '{0}' version '{1}' build failed due reason: {2}" -f $_.ToString() | Write-Warning
    $FailedBuilds += $Package
  }
}

# 04. Copy the results.json
Copy-Item -Path (Join-Path -Path $AvmPackageBuildRoot -ChildPath "results.json") -Destination (Join-Path -Path $AvmPackagePublishRoot -ChildPath "results.json") -Force
