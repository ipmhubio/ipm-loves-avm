# Online readme: https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/
# CSV: https://github.com/Azure/Azure-Verified-Modules/blob/main/docs/static/module-indexes/BicepResourceModules.csv
[CmdletBinding()]
Param(
  [Parameter(Mandatory = $True)]
  [String] $AvmRepositoryRootPath,

  [Parameter(Mandatory = $True)]
  [String] $AvmPackageBuildRoot,

  [Parameter(Mandatory = $False)]
  [String] $IpmHubOrganizationName = "avm-bicep",

  [Parameter(Mandatory = $False)]
  [PsCustomObject[]] $AvmModulesToSkip = $((Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath "settings.jsonc") -Encoding "UTF8" -Raw | ConvertFrom-Json).avmModulesToSkip),

  [Parameter(Mandatory = $False)]
  [String] $FromCommit
)

$ScriptFolder = $PSScriptRoot
Import-Module (Join-Path -Path $ScriptFolder -ChildPath "avm-to-ipm-module.psm1") -Force
$AvmSubFolder = Join-Path -Path $AvmRepositoryRootPath -ChildPath "avm"
If (-not(Test-Path -Path $AvmSubFolder))
{
  Throw ("Could not find folder 'avm' within given path '{0}'." -f $AvmRepositoryRootPath) 
}

# Ensure the build folder exists.
If (-not (Test-Path -Path $AvmPackageBuildRoot -PathType "Container"))
{
  New-Item -Path $AvmPackageBuildRoot -ItemType "Directory" | Out-Null
}

# 01. We need to be on the main branch to make sure that we gather the latest data.
"Setting local repo to main branch and retrieve latest data..." | Write-Host -ForegroundColor "DarkYellow"
$SavedLocation = (Get-Location).Path
Set-Location -Path $AvmRepositoryRootPath
& git switch main > $null 2>&1
& git pull > $null 2>&1
& git fetch --tags > $null 2>&1

$AvmModules = [System.Collections.ArrayList]@()
$ReferencedModulesToRetrieve = [System.Collections.ArrayList]@()
$ReferencestoRetrieveQueue = [System.Collections.Queue]::new()

# 02. Prepare a list of additional files that should be included per module/package.
$AdditionalFiles = @(
  [HashTable] @{
    RelativePath = "."
    Source = Join-Path -Path $AvmRepositoryRootPath -ChildPath "LICENSE"
    DestinationName = "LICENSE.txt"
  },
  [HashTable] @{
    RelativePath = "."
    Source = Join-Path -Path $ScriptFolder -ChildPath "DISCLAIMER.md"
  },
  [HashTable] @{
    RelativePath = "."
    Source = Join-Path -Path $ScriptFolder -ChildPath "bicepconfig.json"
  }
)

# 03. Get a whole list of ALL AVM modules that can be found with as much as metadata that we can gather from this branch.
If ([String]::IsNullOrEmpty($FromCommit))
{
  "Retrieving all AVM modules within the main branch..." | Write-Host
  $ModuleMetadata = Get-AvmModuleMetadata -AvmRootFolder $AvmSubFolder -ResourceModules -UtilityModules -Verbose:$VerbosePreference
  "Found a total of {0} AVM modules, with {1} referenced modules within the main branch." -f $ModuleMetadata.Modules.Count, $ModuleMetadata.ReferencedModules.Count | Write-Host

  # Filter referenced modules that we still need to gather.
  $AllReferencedModulesToRetrieve = [Array] ($ModuleMetadata.ReferencedModules | Where-Object { $False -eq $_.IsPresent }) ?? @()
  "{0} referenced modules are not available within the main branch." -f $AllReferencedModulesToRetrieve.Count | Write-Host
  $ReferencedModulesToRetrieve.AddRange($AllReferencedModulesToRetrieve)
  
  # 03b. Per AVM module, we can start a 'build' preparation to another location. From there we check for other missing components
  Get-ChildItem -Path $AvmPackageBuildRoot | Remove-Item -Recurse -Force
  ForEach($AvmModule in $ModuleMetadata.Modules)
  {
    If ($AvmModule.AcrName -in $AvmModulesToSkip.name -or $AvmModule.IpmHubName -in $AvmModulesToSkip.name)
    {
      "Found AVM module '{0}', but this is on the ignore list. Skipping for copy." -f $AvmModule.AcrName | Write-Warning
      Continue
    }

    $AvmModules.Add($AvmModule) | Out-Null
    Copy-AvmModuleForBuild -AvmModule $AvmModule -BuildRoot $AvmPackageBuildRoot -IpmHubOrganizationName $IpmHubOrganizationName -AdditionalFiles $AdditionalFiles
  }
} `
Else
{
  # Retrieve all commits that were done after the given one, and retrieve the published modules on top of those commits.
  # These can be found by their corresponding TAG.
  $PublishedTags = Get-AvmGitFutureCommitsWithTags -AfterCommitId $FromCommit -ResourceModules -UtilityModules
  Get-ChildItem -Path $AvmPackageBuildRoot | Remove-Item -Recurse -Force
  ForEach($PublishedTagDetails in $PublishedTags)
  {
    "Retrieving module classified as a {0} from published tag '{1}' and commit '{2}'..." -f $PublishedTagDetails.Classification, $PublishedTagDetails.TagName, $PublishedTagDetails.CommitId | Write-Host -ForegroundColor "DarkGray"
    "Switching local repo to tag '{0}'..." -f $PublishedTagDetails.TagName | Write-Host -ForegroundColor "DarkYellow"
    & git checkout $PublishedTagDetails.TagName > $null 2>&1
    $ModuleMetadataSingle = Get-AvmModuleMetadata -AvmRootFolder $AvmSubFolder -ResourceModules -UtilityModules -FilterByPublicName $PublishedTagDetails.Name -Verbose:$VerbosePreference
    $ModuleChild = $ModuleMetadataSingle.Modules | Select-Object -First 1

    If ($ModuleChild.AcrName -in $AvmModulesToSkip.name -or $ModuleChild.IpmHubName -in $AvmModulesToSkip.name)
    {
      "Found AVM module '{0}', but this is on the ignore list. Skipping for copy." -f $AvmModule.AcrName | Write-Warning
      Continue
    }

    $AvmModules.Add($ModuleChild) | Out-Null

    # Filter referenced modules that we need to gather.
    If ($ModuleMetadataSingle.ReferencedModules.Count -gt 0)
    {
      $ModuleChildReferencedModulesToRetrieve = [Array] ($ModuleMetadataSingle.ReferencedModules) ?? @()
      "{0} referenced module(s) should be retrieved for this published tag." -f $ModuleChildReferencedModulesToRetrieve.Count | Write-Host -ForegroundColor "DarkGray"
      $ModuleChildReferencedModulesToRetrieve | ForEach-Object { 
        If (-not ($_.Tag -in $ReferencedModulesToRetrieve.Tag))
        {
          $ReferencedModulesToRetrieve.Add($_) | Out-Null
        }
      }      
    }

    # 03b. Per AVM module, we can start a 'build' preparation to another location. From there we check for other missing components
    Copy-AvmModuleForBuild -AvmModule $ModuleChild -BuildRoot $AvmPackageBuildRoot -IpmHubOrganizationName $IpmHubOrganizationName -AdditionalFiles $AdditionalFiles

    "" | Write-Host
  }
}

# 04. We also make builds for all referenced modules (older) versions
If ($ReferencedModulesToRetrieve.Count -gt 0)
{
  $ReferencestoRetrieveQueue = [System.Collections.Queue]::new()
  $ReferencedModulesToRetrieve | ForEach-Object { $ReferencestoRetrieveQueue.Enqueue($_) }

  "Starting creating builds for referenced modules. The queue now holds {0} items..." -f $ReferencestoRetrieveQueue.Count | Write-Host
  While ($ReferencestoRetrieveQueue.Count -gt 0) 
  {
    $RefModule = $ReferencestoRetrieveQueue.Dequeue()

    "Retrieving referenced module '{0}' version '{1}'..." -f $RefModule.Name, $RefModule.Version | Write-Host -ForegroundColor "DarkGray"
    "Switching local repo to tag '{0}'..." -f $RefModule.Tag | Write-Host -ForegroundColor "DarkYellow"
    & git checkout $RefModule.Tag > $null 2>&1
    $RefModuleMetadata = Get-AvmModuleMetadata -AvmRootFolder $AvmSubFolder -ResourceModules -UtilityModules -FilterByPublicName $RefModule.Name -Verbose:$VerbosePreference

    "Building referenced module '{0}' version '{1}'..." -f $RefModule.Name, $RefModule.Version | Write-Host -ForegroundColor "DarkGray"
    $RefModuleChild = $RefModuleMetadata.Modules | Select-Object -First 1
    Copy-AvmModuleForBuild -AvmModule $RefModuleChild -BuildRoot $AvmPackageBuildRoot -IpmHubOrganizationName $IpmHubOrganizationName -AdditionalFiles $AdditionalFiles -Verbose:$VerbosePreference

    # If this module also has nested modules, we should add this to the queue.
    $InnerReferencedModulesToRetrieve = [Array] ($RefModuleMetadata.ReferencedModules) ?? @()
    If ($InnerReferencedModulesToRetrieve.Count -gt 0)
    {
      "Found {0} inner referenced modules. Adding them to queue." -f $InnerReferencedModulesToRetrieve.Count | Write-Host -ForegroundColor "DarkGray"
      $InnerReferencedModulesToRetrieve | ForEach-Object { $ReferencestoRetrieveQueue.Enqueue($_) }
    }

    "" | Write-Host
  }
}

"Switching local repo back to main..." | Write-Host -ForegroundColor "DarkYellow"
& git switch main > $null 2>&1

# 05. Save results as JSON to our build folder.
$OutputFile = Join-Path -Path $AvmPackageBuildRoot -ChildPath "results.json"
[PsCustomObject] @{
  Modules = $AvmModules | Select-Object -ExcludeProperty "RootPath", "RootName", "BicepFile", "ReadmeFile", "ItemsToInclude"
  References = $ReferencedModulesToRetrieve
  FromCommit = $FromCommit
  TilCommit = Get-GitAvmLastCommitId
} | ConvertTo-Json -Depth 100 | Out-File -Path $OutputFile -Encoding "UTF8"

"Output was saved to '{0}'" -f $OutputFile | Write-Host
Set-Location -Path $SavedLocation