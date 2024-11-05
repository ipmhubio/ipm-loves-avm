[CmdletBinding()]
Param(
  [Parameter(Mandatory = $True)]
  [String] $AvmPackageBuildRoot,

  [Parameter(Mandatory = $True)]
  [String] $TestRootPath
)

# 01a. Prepare our test root path
If (-not (Test-Path -Path $TestRootPath -PathType "Container")) 
{
  New-Item -Path $TestRootPath -ItemType "Directory" | Out-Null
}

# 01b. Make sure the test root path is empty.
Get-ChildItem -Path $TestRootPath | Remove-Item -Recurse -Force

# 01. Copy all folders and files within the $AvmPackageBuildRoot folder to the $TestRootPath
$PackagesWithinBuildFolder = Get-ChildItem -Path $AvmPackageBuildRoot -Directory
"Found {0} packages within the build folder. Creating shadow copy for tests..." -f $PackagesWithinBuildFolder.Count | Write-Host
Copy-Item -Path ("{0}\*" -f $AvmPackageBuildRoot) -Destination $TestRootPath -Recurse -Force | Out-Null

# 02. Search for all ipmhub.json files within the $TestRootPath folder recursive
$IPMHubConfigurationFiles = Get-ChildItem -Path $TestRootPath -Filter 'ipmhub.json' -Recurse
"Found {0} packages that holds an IPMHub configuration file. Preparing nested packages..." -f $IPMHubConfigurationFiles.Count | Write-Host

# 02b. Store the configurations that should be taken into account, in a queue to support nested packages.
$IPMHubConfigurationFilesQueue = [System.Collections.Queue]::new()
$IPMHubConfigurationFiles | ForEach-Object { $IPMHubConfigurationFilesQueue.Enqueue($_) }

# 03. Loop through all these files, and within the folder of the file, create a new folder 'packages' 
While($IPMHubConfigurationFilesQueue.Count -gt 0)
{
  $ConfigurationFile = $IPMHubConfigurationFilesQueue.Dequeue()
  $ConfigurationFileObj = Get-Content -Path $ConfigurationFile.FullName -Encoding "UTF8" -Raw | ConvertFrom-Json -Depth 10
  $RelativePath = $ConfigurationFile.FullName.Replace($TestRootPath, "").replace("ipmhub.json", "")
  $PackagePackagesFolder = Join-Path -Path $ConfigurationFile.Directory -ChildPath 'packages'

  "Preparing IPMHub workspace for folder '{0}'..." -f $RelativePath | Write-Host

  # 03a. Check if the 'packages' folder exists for this package. If not, create it.
  If (-not (Test-Path -Path $PackagePackagesFolder -PathType "Container")) 
  {
    New-Item -Path $PackagePackagesFolder -ItemType "Directory" | Out-Null
  }

  # 03b. Now loop through all required nested packages and make sure it exists
  ForEach($NestedPackage in $ConfigurationFileObj.packages)
  {
    # Find the nested package within the root folder
    $NestedPackageName = ($NestedPackage.name -split "/") | Select-Object -Last 1
    $NestedPackageRootPath = Join-Path $TestRootPath -ChildPath $NestedPackageName
    If (-not (Test-Path -Path $NestedPackageRootPath))
    {
      Throw ("Could not find nested package '{0}' for IPMHub workspace '{1}' within the test folder. Cannot proceed." -f $NestedPackageName, $RelativePath)
    }

    $Versions = $NestedPackage.versions ?? @($NestedPackage.version)
    ForEach($Version in $Versions)
    {
      $Source = Join-Path $NestedPackageRootPath -ChildPath $Version
      $Destination = Join-Path -Path $PackagePackagesFolder -ChildPath $NestedPackageName
      "Copying version '{0}' of nested package '{1}' to '{2}'..." -f $Version, $NestedPackageName, $Destination | Write-Verbose
      New-Item -Path $Destination -ItemType "Directory" -Force | Out-Null
      Copy-Item -Path ("{0}\*" -f $Source) -Destination $Destination -Recurse -Force | Out-Null

      # If there are nested packages, add to the queue
      $InnerNestedPackageIpmHubConfigFilePath = Join-Path $Destination -ChildPath "ipmhub.json"
      If (Test-Path -Path $InnerNestedPackageIpmHubConfigFilePath -PathType "Leaf")
      {
        "Nested package '{0}' version '{1}' has inner nested packages. Adding to the queue." -f $NestedPackageName, $Version | Write-Verbose
        $IPMHubConfigurationFilesQueue.Enqueue((Get-Item -Path $InnerNestedPackageIpmHubConfigFilePath))
      }
    }
  }
}