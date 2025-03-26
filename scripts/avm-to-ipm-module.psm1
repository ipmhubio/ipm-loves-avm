<#

SHARED VARIABLES

#>
# Online readme: https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/
# CSV: https://github.com/Azure/Azure-Verified-Modules/blob/main/docs/static/module-indexes/BicepResourceModules.csv

Function Get-AvmGitRepositoryCurrentBranchOrTagName
{
  [OutputType([String])]
  [CmdletBinding()]

  $CurrentCommitId = & git rev-parse HEAD
  $CurrentTag = git describe --tags --exact-match $CurrentCommitId 2>$null
  If ($CurrentTag)
  {
    $CurrentTag
    Return
  }

  $CurrentBranch = & git symbolic-ref --short -q HEAD
  $CurrentBranch
}

Function Get-AvmClassificationFromName
{
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $True, ValueFromPipeline)]
    [String] $Name
  )

  If ($Name -like "*/res/*")
  {
    "ResourceModule"
  } `
  ElseIf ($Name -like "*/ptn/*")
  {
    "PatternModule"
  } `
  ElseIf ($Name -like "*/utl/*")
  {
    "UtilityModule"
  } `
  Else
  {
    "Unknown"
  }
}

Function Get-GitAvmLastCommitId
{
  [OutputType([String])]
  [CmdletBinding()]
  Param()

  $CommitId = & git log -n 1 --pretty=format:"%H" main
  $CommitId
}

Function Get-AvmGitFutureCommitsWithTags
{
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $True)]
    [String] $AfterCommitId,

    [Parameter(Mandatory = $False)]
    [Switch] $ResourceModules,

    [Parameter(Mandatory = $False)]
    [Switch] $PatternModules,

    [Parameter(Mandatory = $False)]
    [Switch] $UtilityModules
  )

  # Get our commit date based on the given commit id.
  $CommitDate = & git show -s --format=%cd --date=iso-strict $AfterCommitId

  # Use this date to retrieve the log of commits after that
  $NewerCommits = git log main --pretty=format:"%H %cd" --reverse --date=iso-strict --since="$CommitDate"

  # Loop through this commit list and check if there is a git tag on it that we are interested in.
  # The list if from older to newer.
  ForEach ($Commit in $NewerCommits)
  {
    $CommitParts = $Commit -split ' '
    $CommitId = $CommitParts | Select-Object -First 1
    $CommitDate = $CommitParts | Select-Object -Last 1
    $Tag = git tag --points-at $CommitId 2>$null
    If ($Null -ne $Tag)
    {
      If (-not($ResourceModules.IsPresent -and $True -eq $ResourceModules) -and $Tag.StartsWith("avm/res"))
      {
        Continue
      }

      If (-not($PatternModules.IsPresent -and $True -eq $PatternModules) -and $Tag.StartsWith("avm/ptn"))
      {
        Continue
      }

      If (-not($UtilityModules.IsPresent -and $True -eq $UtilityModules) -and $Tag.StartsWith("avm/utl"))
      {
        Continue
      }

      $TagParts = $Tag -split "/"
      [PsCustomObject] @{
        CommitId = $CommitId
        Date = $CommitDate
        Name = ($TagParts | Select-Object -Skip 2 | Select-Object -SkipLast 1) -join "/"
        Version = $TagParts | Select-Object -Last 1
        Classification = Get-AvmClassificationFromName -Name $Tag
        TagName = $Tag
      }
    }
  }
}

Function Get-AvmGitRepositoryPublishedModules
{
  [OutputType([PsCustomObject[]])]
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $False)]
    [Switch] $ResourceModules,

    [Parameter(Mandatory = $False)]
    [Switch] $PatternModules,

    [Parameter(Mandatory = $False)]
    [Switch] $UtilityModules
  )

  # 01. Get a list of all tags that indicate a published module, specific on the current branch/tag.
  $AvmPublishedModuleList = (& git tag --merged) `
  | Where-Object {
    ($ResourceModules.IsPresent -and $True -eq $ResourceModules -and $_.StartsWith("avm/res/")) -or
    ($PatternModules.IsPresent -and $True -eq $PatternModules -and $_.StartsWith("avm/ptn/")) -or
    ($UtilityModules.IsPresent -and $True -eq $UtilityModules -and $_.StartsWith("avm/utl/"))
  } `
  | ForEach-Object {
    $Parts = $_ -split "/"
    $Name = ($Parts | Select-Object -Skip 2 | Select-Object -SkipLast 1) -join "/"
    $Version = $Parts | Select-Object -Last 1
    [PsCustomObject] @{
      Name = $Name
      Version = $Version;
      Classification = $_ | Get-AvmClassificationFromName
      TagName = $_;
      PublishedOn = $Null
      IsLatest = $False
    }
  } | Where-Object { $_.Classification -ne "Unknown" }

  # 02. Get a list of all commits that have been done on this git repository.
  $AllCommitsWithDates = (& git log main --pretty=format:"%H;%cd" --reverse --date=iso-strict --since "2022-01-01T00:00:00+02:00") | ForEach-Object {
    $Parts = $_ -split ";"
    [PsCustomObject] @{
      CommitId = $Parts[0]
      CommitDate = $Parts[1]
    }
  }

  # 03. Append the tag publish date to the previous list of tags.
  $AllTagsResults = (& git for-each-ref --format="%(refname:short);%(objectname)" refs/tags)
  ForEach($AllTagResult in $AllTagsResults)
  {
    $Parts = $AllTagResult -split ";"
    $TagName = $Parts[0]
    $CommitId = $Parts[1]
    $CommitFound = $AllCommitsWithDates | Where-Object { $_.CommitId -eq $CommitId } | Select-Object -First 1
    $PublishedModuleFound = $AvmPublishedModuleList | Where-Object { $_.TagName -eq $TagName } | Select-Object -First 1
    If (-not($CommitFound) -or -not($PublishedModuleFound)) { Continue }

    $CommitDate = [DateTimeOffset]::Parse($CommitFound.CommitDate).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $PublishedModuleFound.PublishedOn = $CommitDate
  }

  # 04. We are mostly interested in the 'latest' versions of the module, that must be the one in main now.
  ForEach($UniqueModule in ($AvmPublishedModuleList | Group-Object -Property "Name"))
  {
    $LatestVersion = $UniqueModule.Group.Version | ForEach-Object { [Version] $_ } | Sort-Object -Descending | Select-Object -First 1
    $LatestAvmModuleFound = $AvmPublishedModuleList | Where-Object { $_.Name -eq $UniqueModule.Name -and ([Version]$_.Version) -eq $LatestVersion }
    $LatestAvmModuleFound.IsLatest = $True
  }

  $AvmPublishedModuleList
}

Function Search-PublicRegistryModuleReference
{
  [CmdletBinding()]
  Param(
    [String[]] $FileContent
  )

  $FoundReferences = @()
  ForEach($Line in $FileContent)
  {
    If ($Line -like "*br/public:avm/*")
    {
      # When referring to a specific version (mostly within BICEP files), we can extract the exact version.
      If ($Line -match "br/public:avm/(res|ptn|utl)/(.+):([0-9]{1,3}\.[0-9]{1,4}\.[0-9]{1,6})")
      {
        $Type = $Matches[1]
        $Name = $Matches[2]
        $Version = $Matches[3]
      } `
      # When referring to a <version>, this occurs most of the time within a MD file for examples.
      ElseIf($Line -match "br/public:avm/(res|ptn|utl)/(.+):<version>")
      {
        $Type = $Matches[1]
        $Name = $Matches[2]
        $Version = "<version>"
      }

      Switch ($Type) {
        "res" { $ModuleClassification = "ResourceModule" }
        "ptn" { $ModuleClassification = "PatternModule" }
        "utl" { $ModuleClassification = "UtilityModule" }
        Default {
          # Not supported
          Continue
        }
      }

      $FoundReference = $FoundReferences | Where-Object { $_.Name -eq $Name }
      If ($Null -ne $FoundReference)
      {
        $FoundReference.Versions += $Version
        $FoundReference.Versions = [Array] ($FoundReference.Versions | Select-Object -Unique)
      } `
      Else
      {
        $FoundReference = [PsCustomObject] @{ Name = $Name; Classification = $ModuleClassification; Versions = @($Version); }
        $FoundReferences += $FoundReference
      }
    }
  }

  $FoundReferences
}

Function Search-RelevantModuleFiles
{
  [CmdletBinding()]
  Param(
    [String] $RootPath,

    [String] $ParentRelativePath,

    [Switch] $IsRoot
  )

  If ($IsRoot.IsPresent -and $True -eq $IsRoot)
  {
    $RelativePath = ""
    $ChildRelativePath = ""
  } `
  ElseIf ([String]::IsNullOrWhiteSpace($ParentRelativePath))
  {
    $RelativePath = Split-Path -Path $RootPath -LeafBase
    $ChildRelativePath = "{0}{1}" -f $RelativePath, [System.IO.Path]::DirectorySeparatorChar
  }
  Else
  {
    $RelativePath = Split-Path -Path $RootPath -LeafBase
    $ChildRelativePath = "{0}{1}{2}{3}" -f $ParentRelativePath.TrimEnd('/').TrimEnd('\'), [System.IO.Path]::DirectorySeparatorChar, $RelativePath, [System.IO.Path]::DirectorySeparatorChar
  }

  $Items = [System.Collections.ArrayList]@()
  $ChildItems = Get-ChildItem -Path $RootPath -Directory | Where-Object { $_.Name -ne "tests" }
  ForEach($ChildItem in $ChildItems)
  {
    $InnerChildItems = (Search-RelevantModuleFiles -RootPath $ChildItem.FullName -ParentRelativePath $ChildRelativePath).ChildItems ?? @()
    $Items.Add([PsCustomObject] @{
      Name = $ChildItem.Name
      FullName = $ChildItem.FullName
      RelativePath = ("{0}{1}" -f $ChildRelativePath, $ChildItem.FullName.Substring($RootPath.Length).TrimStart('\').TrimStart('/'))
      Type = "Directory"
      ChildItems = $InnerChildItems
    }) | Out-Null
  }

  $Files = Get-ChildItem -Path $RootPath -File | Where-Object { $_.Name -notin @("main.json", "version.json", "ORPHANED.md") }
  ForEach($FileItem in $Files)
  {
    $FileResult = [PsCustomObject] @{
      Name = $FileItem.Name
      FullName = $FileItem.FullName
      RelativePath = ("{0}{1}" -f $ChildRelativePath, $FileItem.FullName.Substring($RootPath.Length).TrimStart('\').TrimStart('/'))
      Type = "File"
      ReferencedModules = @()
    }

    # If the file is a BICEP or MD file, we should look for references to public registry modules.
    # If so, we also supply a possible replacement, based on the info that we know right now.
    If ($FileItem.Extension -in @(".bicep", ".md"))
    {
      $FileContent = Get-Content -Path $FileItem.FullName -Encoding "UTF8"
      $FileResult.ReferencedModules = [Array](Search-PublicRegistryModuleReference -FileContent $FileContent) ?? @()
    }

    $Items.Add($FileResult) | Out-Null
  }

  [PsCustomObject] @{
    Name = Split-Path -Path $RootPath -LeafBase
    FullName = $RootPath
    RelativePath = $ChildRelativePath.TrimEnd('/').TrimEnd('\')
    ChildItems = $Items.ToArray()
  }
}

Function Convert-AvmModuleMetadataItemsToFlat
{
  [CmdletBinding(DefaultParameterSetName = "ByModule")]
  Param(
    [Parameter(Mandatory = $True, ParameterSetName = "ByModule")]
    [PsCustomObject] $AvmModule,

    [Parameter(Mandatory = $True, ParameterSetName = "ByItems")]
    [Object[]] $Items
  )

  If ($PSCmdlet.ParameterSetName -eq "ByModule")
  {
    $Items = $AvmModule.ItemsToInclude
  }

  $Results = [System.Collections.ArrayList]@()
  ForEach($Item in $Items)
  {
    If ($Item.Type -eq "Directory")
    {
      Convert-AvmModuleMetadataItemsToFlat -Items $Item.ChildItems | ForEach-Object { $Results.Add($_) | Out-Null }
    } `
    Else
    {
      $Results.Add($Item) | Out-Null
    }
  }

  $Results.ToArray()
}

Function Get-AvmModuleMetadata
{
  [OutputType([PsCustomObject])]
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [String] $AvmRootFolder,

    [Parameter(Mandatory = $False)]
    [Switch] $ResourceModules,

    [Parameter(Mandatory = $False)]
    [Switch] $PatternModules,

    [Parameter(Mandatory = $False)]
    [Switch] $UtilityModules,

    [Parameter(Mandatory = $False)]
    [String[]] $FilterByPublicName,

    [Parameter(Mandatory = $False)]
    [PsCustomObject[]] $IpmHubNameReplacements
  )

  $AvmResFolderRoot = Join-Path $AvmRootFolder -ChildPath "res"
  # $AvmPtnFolderRoot = Join-Path $AvmRootFolder -ChildPath "ptn"
  $AvmUtlFolderRoot = Join-Path $AvmRootFolder -ChildPath "utl"

  # Ensure directories exist
  if (-not (Test-Path -Path $AvmRootFolder)) {
    New-Item -Path $AvmRootFolder -ItemType Directory -Force | Out-Null
    "{0} - Created root directory '{1}' because it did not exist." -f $MyInvocation.MyCommand, $AvmRootFolder | Write-Verbose
  }

  if (-not (Test-Path -Path $AvmResFolderRoot)) {
    New-Item -Path $AvmResFolderRoot -ItemType Directory -Force | Out-Null
    "{0} - Created resource modules directory '{1}' because it did not exist." -f $MyInvocation.MyCommand, $AvmResFolderRoot | Write-Verbose
  }

  if (-not (Test-Path -Path $AvmUtlFolderRoot)) {
    New-Item -Path $AvmUtlFolderRoot -ItemType Directory -Force | Out-Null
    "{0} - Created utility modules directory '{1}' because it did not exist." -f $MyInvocation.MyCommand, $AvmUtlFolderRoot | Write-Verbose
  }

  # 01. We first need to gather the list of published AVM modules from the current branch
  $AvmPublishedModuleListLatest = Get-AvmGitRepositoryPublishedModules -ResourceModules -UtilityModules | Where-Object { $True -eq $_.IsLatest } | Select-Object -ExcludeProperty "IsLatest"

  $Modules = [System.Collections.ArrayList]@()
  $Modules.Clear()

  # We always retrieve all  modules, because there can be references. We should filter them out at the end if needed.
  $VersionFiles = @(
    Get-ChildItem -Path $AvmUtlFolderRoot -Filter "version.json" -Recurse -ErrorAction SilentlyContinue
    Get-ChildItem -Path $AvmResfolderRoot -Filter "version.json" -Recurse -ErrorAction SilentlyContinue
    # Get-ChildItem -Path $AvmPtnFolderRoot -Filter "version.json" -Recurse
  )

  ForEach($VersionFile in $VersionFiles)
  {
    $ModuleRoot = $VersionFile.Directory.FullName
    $VersionInfo = Get-Content -Path $VersionFile -Raw -Encoding "UTF8" | ConvertFrom-Json
    $BicepFile = Join-Path -Path $ModuleRoot -ChildPath "main.bicep"
    $ReadmeFile = Join-Path -Path $ModuleRoot -ChildPath "README.md"

    # Which files should be included within the package?
    $ModuleFiles = (Search-RelevantModuleFiles -RootPath $ModuleRoot -IsRoot).ChildItems

    # Do we have a list of (unique) referenced modules that we need to know about?
    $ReferencedModules = @()
    $ModuleFilesFlat = Convert-AvmModuleMetadataItemsToFlat -Items $ModuleFiles
    ForEach($FileReferencedModule in $ModuleFilesFlat.ReferencedModules)
    {
      $Versions = [Array] ($FileReferencedModule.Versions | Where-Object { $_ -ne "<version>" }) ?? @() # We can ignore the docs versions.
      If ($Versions.Count -eq 0) { Continue }

      $Name = $FileReferencedModule.Name
      $Classification = $FileReferencedModule.Classification
      $ReferencedModule = $ReferencedModules | Where-Object { $_.Name -eq $Name }
      If ($Null -eq $ReferencedModule)
      {
        $ReferencedModule = @{
          Name = $Name
          IpmHubName = ""
          Classification = $Classification
          Versions = @()
        }

        $ReferencedModules += $ReferencedModule
      }

      ForEach($Version in $Versions)
      {
        If ($ReferencedModule.Versions -notcontains $Version)
        {
          $ReferencedModule.Versions += $Version
        }
      }
    }

    # Read metadata from bicep file
    $BicepFileContent = Get-Content -Path $BicepFile -Encoding "UTF8" | Select-Object -First 20

    # Read metadata from README
    $ReadmeFileContent = Get-Content -Path $ReadmeFile -Encoding "UTF8" | Select-Object -First 50
    $ReadmeModuleAzureType = "unknown"
    $ReadmeModuleClassification = "unknown"
    $ReadmePublicBicepRegistryIdentification = "unknown"
    ForEach($Line in $ReadmeFileContent)
    {
      If ($Null -eq $Line -or $Line.Length -eq 0)
      {
        Continue
      }

      If ($ReadmeModuleAzureType -eq "unknown" -and $Line.StartsWith("# ") -and $Line -match "^#\s+(.+\s?)``\[(.+)\]``$")
      {
        $ReadmeModuleAzureType = $Matches[2]
        Continue
      }

      If ($ReadmePublicBicepRegistryIdentification -eq "unknown" -and $Line -match "br/public:avm/(res|ptn|utl)/(.+):(<version>|\d\.\d\.\d)")
      {
        $ReadmeModuleClassification = Get-AvmClassificationFromName -Name $Line
        $ReadmePublicBicepRegistryIdentification = $Matches[2]
        Continue
      }
    }

    # Lets try to get our exact module version from our git history
    $ExactAvmModule = $AvmPublishedModuleListLatest | Where-Object { $_.Name -eq $ReadmePublicBicepRegistryIdentification } | Select-Object -First 1

    # Extract our description from the BICEP file. We have 2 variants, single line and multiline.
    $Description = ($BicepFileContent | Where-Object { $_ -like "metadata description =*" } | Select-Object -First 1) -replace "metadata\s*description\s*=\s*", ""
    If ($Description -like "'''*") # Multiline
    {
      If ($Description -ne "'''") # Only found within the common types for now
      {
        $Description = $Description.Replace("'''", "")
      } `
      Else
      {
        # TODO: Support multiline descriptions
        $Description = ""
      }
    } `
    Else
    {
      $Description = $Description -split "'" | Select-Object -Skip 1 | Select-Object -First 1
    }

    $ModuleToAdd = [PsCustomObject] @{
      Name = ($BicepFileContent | Where-Object { $_ -like "metadata name =*" } | Select-Object -First 1) -split "'" | Select-Object -Skip 1 -First 1
      AcrName = $ReadmePublicBicepRegistryIdentification
      IpmHubName = ""
      Classification = $ReadmeModuleClassification
      AzureType = $ReadmeModuleAzureType
      PublishedOn = $ExactAvmModule.PublishedOn
      Description = $Description
      RootPath = $ModuleRoot
      RootName = Split-Path -Path $ModuleRoot -Leaf
      BicepFile = $BicepFile
      Version = $ExactAvmModule.Version ?? $VersionInfo.version
      ReadmeFile = $(If (Test-Path -Path $ReadmeFile) { $ReadmeFile } Else { $Null })
      ItemsToInclude = $ModuleFiles
      ReferencedModules = @()
    }

    $ModuleToAdd.IpmHubName = ($ModuleToAdd.Name -replace " ", "-").ToLowerInvariant()
    $ModuleToAdd.IpmHubName = $ModuleToAdd.IpmHubName.Replace("(", "").Replace(")", "").Replace("\", "-").Replace("/", "-")

    # Now make sure that our ipm hub gets possible replacements
    ForEach($Replacement in $IpmHubNameReplacements)
    {
      $ModuleToAdd.IpmHubName = $ModuleToAdd.IpmHubName -replace $Replacement.search, $Replacement.replacement
    }

    $ModuleToAdd.IpmHubName = $ModuleToAdd.IpmHubName.TrimStart('-').TrimEnd('-')

    # Append a prefix for specific classifications
    If ($ModuleToAdd.Classification -eq "UtilityModule")
    {
      $ModuleToAdd.IpmHubName = "utl-{0}" -f $ModuleToAdd.IpmHubName
    } `
    ElseIf ($ModuleToAdd.Classification -eq "PatternModule")
    {
      $ModuleToAdd.IpmHubName = "ptn-{0}" -f $ModuleToAdd.IpmHubName
    }

    # Add all referenced modules to our object
    # There are situations where the referenced modules contains a reference to itself. We ignore those.
    ForEach($RefModule in $ReferencedModules)
    {
      If ($RefModule.Name -ne $ModuleToAdd.AcrName)
      {
        $ModuleToAdd.ReferencedModules += $RefModule
      } `
      Else
      {
        $Versions = ($RefModule.Versions | Where-Object { $_ -ne $ModuleToAdd.Version }) ?? @()
        If ($Versions.Count -eq 0)
        {
          Continue # Ignore references to ourself
        }

        $RefModule.Versions = $Versions
        $ModuleToAdd.ReferencedModules += $RefModule
      }
    }

    $Modules.Add($ModuleToAdd) | Out-Null
  }

  # We have a complete list of all AVM modules. Now, we can fix possible references to their IPMHub name.
  $ModulesWithReferencedModules = $Modules | Where-Object { $_.ReferencedModules.Count -gt 0 }
  ForEach($Module in $ModulesWithReferencedModules)
  {
    ForEach($RefModule in $Module.ReferencedModules)
    {
      # Find the module based on their acr name.
      $FoundModule = $Modules | Where-Object { $_.AcrName -eq $RefModule.Name }
      If ($Null -ne $FoundModule)
      {
        $RefModule.IpmHubName = $FoundModule.IpmHubName
      }
    }
  }

  # Now we aggregate our data and prepare a result object
  $AllReferencedModulesByName = ($Modules.ReferencedModules | Group-Object -Property Name)
  $AllReferencedModulesToRetrieve = $AllReferencedModulesByName | ForEach-Object {
    $ReferencedModuleName = $_.Name
    $ReferencedmoduleClassification = $_.Group[0].Classification
    $Versions = [Array] ($_.Group.Versions | Select-Object -Unique) ?? @()
    "{0} - Referenced module '{1}' is used {2} times." -f $MyInvocation.MyCommand, $ReferencedModuleName, $_.Group.Count | Write-Verbose
    ForEach($Version in $Versions)
    {
      $ReferencedModuleExists = $Modules | Where-Object { $_.AcrName -eq $ReferencedModuleName -and $_.Version -eq $Version }
      $TagValue = Switch ($ReferencedmoduleClassification) {
        "ResourceModule" { "avm/res/{0}/{1}" -f $ReferencedModuleName, $Version }
        "PatternModule" { "avm/ptn/{0}/{1}" -f $ReferencedModuleName, $Version }
        "UtilityModule" { "avm/utl/{0}/{1}" -f $ReferencedModuleName, $Version }
        Default { "" }
      }

      [PsCustomObject] @{
        Name = $ReferencedModuleName
        IpmHubName = $_.Group[0].IpmHubName
        Version = $Version
        Classification = $ReferencedmoduleClassification
        Tag = $TagValue
        IsPresent = $Null -ne $ReferencedModuleExists
      }
    }
  }

  # Filter out modules if not required.
  $Modules = $Modules | Where-Object { $_.Classification -ne "unknown" }
  If (-not([String]::IsNullOrEmpty($FilterByPublicName)))
  {
    $Modules = [Array] ($Modules | Where-Object { $_.AcrName -eq $FilterByPublicName }) ?? @()
  } `
  Else
  {
    If (-not($ResourceModules.IsPresent -and $True -eq $ResourceModules))
    {
      $Modules = $Modules | Where-Object { $_.Classification -ne "ResourceModule" }
    }

    If (-not($PatternModules.IsPresent -and $True -eq $PatternModules))
    {
      $Modules = $Modules | Where-Object { $_.Classification -ne "PatternModule" }
    }

    If (-not($UtilityModules.IsPresent -and $True -eq $UtilityModules))
    {
      $Modules = $Modules | Where-Object { $_.Classification -ne "UtilityModule" }
    }
  }

  # We should filter out referenced modules that are not needed anymore (due the fact that we filtered out classifications)
  $AllReferencedModulesUnique = $Modules.ReferencedModules | ForEach-Object { $Ref = $_.Name; $_.Versions | ForEach-Object { "{0}:{1}" -f $Ref, $_ } } | Select-Object -Unique
  $AllReferencedModulesToRetrieve = $AllReferencedModulesToRetrieve | Where-Object { ("{0}:{1}" -f $_.Name, $_.Version) -in $AllReferencedModulesUnique }

  [PsCustomObject] @{
    Modules = $Modules
    ReferencedModules = $AllReferencedModulesToRetrieve
  }
}

Function Remove-TelemetryFromBicepFile
{
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $True)]
    [String] $BicepFile,

    [Parameter(Mandatory = $False)]
    [ValidateRange(1,2)]
    [Int] $RemovalMethod = 1
  )

  Begin
  {
    "{0} - START" -f $MyInvocation.MyCommand | Write-Verbose
  }

  Process
  {
    If (-not(Test-Path -Path $BicepFile))
    {
      Throw ("File '{0}' does not exist." -f $BicepFile)
    }

    If ($RemovalMethod -eq 1)
    {
      # Method 1: Disable default value 'enableTelemtry'.
      $BicepContent = Get-Content -Path $BicepFile -Encoding "UTF8" -Raw
      $BicepContent = $BicepContent -replace "param enableTelemetry bool = true", "param enableTelemetry bool = false"
      $BicepContent | Out-File -FilePath $BicepFile -Encoding "UTF8"
      Return
    }

    # Method 2: Remove all telemetry resource data.
    $BicepContent = Get-Content -Path $BicepFile -Encoding "UTF8"
    $FinalBicepContent = New-Object System.Collections.Generic.List[string]
    $TelemetryStart = -1
    $TelemetryEnd = -1
    For ($x = 0; $x -lt $BicepContent.Count; $x++)
    {
      $Line = $BicepContent[$x]
      If ($Null -eq $Line -or $Line.Length -eq 0)
      {
        $FinalBicepContent.Add("")
        Continue
      }

      # If the line starts with '#disable-next-line no-deployments-resources', we can remove it.
      If ($Line -like "#disable-next-line no-deployments-resources*")
      {
        Continue
      }

      If ($Line -like "resource avmTelemetry*")
      {
        # Found the start.
        $TelemetryStart = $x
        Continue
      }

      If ($TelemetryEnd -eq -1 -and $TelemetryStart -gt 0)
      {
        If ($Line.TrimEnd() -eq "}")
        {
          # Found the end
          $TelemetryEnd = $x
        }

        Continue
      }

      $FinalBicepContent.Add($Line)
    }

    If ($TelemetryStart -eq -1)
    {
      "{0} - No telemetry was found within file '{1}'." -f $MyInvocation.MyCommand, $BicepFile | Write-Verbose
    }

    "{0} - Telemetry within file '{1}' was found from line {2} to {3}. Removing..." -f $MyInvocation.MyCommand, $BicepFile, ($TelemetryStart+1), ($TelemetryEnd+1) | Write-Verbose
    Set-Content -Path $BicepFile -Value $FinalBicepContent.ToArray() -Encoding "UTF8" | Out-Null
  }

  End
  {
    "{0} - END" -f $MyInvocation.MyCommand | Write-Verbose
  }
}

Function Add-AdditionalMetadataToBicepFile
{
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $True)]
    [String] $BicepFile,

    [Parameter(Mandatory = $True)]
    [HashTable] $Metadata
  )

  Begin
  {
    "{0} - START" -f $MyInvocation.MyCommand | Write-Verbose
  }

  Process
  {
    If (-not(Test-Path -Path $BicepFile))
    {
      Throw ("File '{0}' does not exist." -f $BicepFile)
    }

    # We go top down, until we detect the 'description' metadata. We insert a 'version' below this.
    # But only if no 'version' metadata exists.
    $BicepContent = Get-Content -Path $BicepFile -Encoding "UTF8" -Raw
    $MetadataKeys = $Metadata.Keys
    $MetadataSearchString = "metadata {0}" -f ($MetadataKeys -join "|metadata ")
    If ($BicepContent -match $MetadataSearchString)
    {
      "{0} - Bicep file '{1}' already contains additional metadata." -f $MyInvocation.MyCommand, $BicepFile | Write-Verbose
      Continue;
    }

    $BicepContent = Get-Content -Path $BicepFile -Encoding "UTF8"
    $FinalBicepContent = New-Object System.Collections.Generic.List[string]
    For ($x = 0; $x -lt $BicepContent.Count; $x++)
    {
      $OwnerFound = $False
      $Line = $BicepContent[$x]
      If ($Null -eq $Line -or $Line.Length -eq 0)
      {
        $FinalBicepContent.Add("")
        Continue
      }

      # Found the description metadata element ?
      $OwnerFound = $Line -like "*metadata owner*"
      If ($OwnerFound)
      {
        "{0} - Found owner on line {1}. Appending metadata..." -f $MyInvocation.MyCommand, ($x+1) | Write-Verbose
        ForEach($Key in $MetadataKeys)
        {
          $FinalBicepContent.Add(("metadata {0} = '{1}'" -f $Key, $Metadata.$Key))
        }
      }

      $FinalBicepContent.Add($Line)
    }

    Set-Content -Path $BicepFile -Value $FinalBicepContent.ToArray() -Encoding "UTF8" | Out-Null
  }

  End
  {
    "{0} - END" -f $MyInvocation.MyCommand | Write-Verbose
  }
}

Function Copy-AvmModuleForBuild
{
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $True)]
    [PsCustomObject] $AvmModule,

    [Parameter(Mandatory = $True)]
    [String] $BuildRoot,

    [Parameter(Mandatory = $True)]
    [String] $IpmHubOrganizationName,

    [Parameter(Mandatory = $False)]
    [HashTable[]] $AdditionalFiles,

    [Parameter(Mandatory = $False)]
    [Switch] $FailOnNonBuildableModule
  )

  Function FailOrWarning($Message)
  {
    If ($FailOnNonBuildableModule.IsPresent -and $True -eq $FailOnNonBuildableModule)
    {
      Throw $Message
    }

    $Message | Write-Warning
  }

  If ($AvmModule.IpmHubName.Length -gt 30)
  {
    FailOrWarning("Cannot build package '{0}'. Its name size exceeds 30 characters. AVM name: '{1}'." -f $AvmModule.IpmHubName, $AvmModule.AcrName)
    Return
  }

  # If the version only contains a major and minor, there is something wrong.
  If (($AvmModule.Version -split "\.").Count -ne 3)
  {
    $VersionValue = $AvmModule.Version | ConvertTo-Json -Depth 2
    FailOrWarning("Cannot build package '{0}'. No published version found. AVM name: '{1}', version value: '{2}'." -f $AvmModule.IpmHubName, $AvmModule.AcrName, $VersionValue)
    Return
  }

  $PackageFolder = Join-Path -Path $BuildRoot -ChildPath $AvmModule.IpmHubName -AdditionalChildPath $AvmModule.Version
  If (Test-Path -Path $PackageFolder)
  {
    "Build path '{0}' already exists. Cleaning up..." -f $PackageFolder | Write-Verbose
    Remove-Item -Path $PackageFolder -Recurse -Force | Out-Null
  }

  New-Item -Path $BuildRoot -Name $AvmModule.IpmHubName -ItemType "Directory" -Force | Out-Null
  $FilesToCopy = Convert-AvmModuleMetadataItemsToFlat -AvmModule $AvmModule

  "Found {0} files to copy..." -f $FilesToCopy.Count | Write-Verbose
  ForEach($Item in $FilesToCopy)
  {
    $Destination = Join-Path -Path $PackageFolder -ChildPath $Item.RelativePath
    $DestinationDirectory = [System.IO.Path]::GetDirectoryName($Destination)
    If (-not (Test-Path $DestinationDirectory))
    {
      New-Item -Path $DestinationDirectory -ItemType Directory -Force | Out-Null
    }

    Copy-Item -Path $Item.FullName -Destination $Destination -Force | Out-Null

    # Update possible references
    If ($Item.Type -eq "File" -and $Item.ReferencedModules.Count -gt 0)
    {
      $FileContent = Get-Content -Path $Destination -Encoding "UTF8" -Raw

      # Replace README references to itself.
      $Search = "br/public:avm/(res|ptn|utl)/{0}:<version>" -f $AvmModule.AcrName
      $Replace = "./packages/{0}/main.bicep" -f $AvmModule.IpmHubName
      $FileContent = $FileContent -replace $Search, $Replace

      # There are situations (errors) where readme's contain the real version. We should replace these too.
      $Search = "br/public:avm/(res|ptn|utl)/{0}:{1}" -f $AvmModule.AcrName, $AvmModule.Version
      $Replace = "./packages/{0}/main.bicep" -f $AvmModule.IpmHubName
      $FileContent = $FileContent -replace $Search, $Replace

      ForEach($Ref in $Item.ReferencedModules)
      {
        $RefIpmHubName = $AvmModule.ReferencedModules | Where-Object { $_.Name -eq $Ref.Name } | Select-Object -First 1 -ExpandProperty "IpmHubName"
        $RefRelativePath = "{0}/" -f (((Split-Path -Path $Item.RelativePath -Parent) -split "[/\\]" | Where-Object { $_ -ne "" } | ForEach-Object { ".." }) -join [System.IO.Path]::DirectorySeparatorChar)
        If ($RefRelativePath.Length -eq 1)
        {
          $RefRelativePath = ".{0}" -f $RefRelativePath
        }

        $ModuleTypes = @("res", "ptn", "utl")
        $RefVersionAddition = ""

        # We should check if there are multiple versions mentioned for this module. We can assume IPM will use the multiple download strategy then.
        $MultipleVersionsAvailable = ([Array] ($AvmModule.ReferencedModules | Where-Object { $_.IpmHubName -eq $RefIpmHubName } | Select-Object -ExpandProperty "Versions") ?? @()).Count -gt 1
        ForEach($RefVersion in $Ref.Versions)
        {
          # If multiple versions for the same referenced module are targeted, we can assume IPM will use the multiple download strategy.
          if ($MultipleVersionsAvailable)
          {
            $RefVersionAddition = "/{0}" -f $RefVersion
          }

          ForEach($ModuleType in ($ModuleTypes))
          {
            $Find = [RegEx]::Escape(("``br/public:avm/{0}/{1}:{2}`` | Remote Reference |" -f $ModuleType, $Ref.Name, $RefVersion))
            $Replace = "``{0}packages/{1}{2}/main.bicep`` | Local Reference |" -f $RefRelativePath, $RefIpmHubName, $RefVersionAddition
            $FileContent = $FileContent -replace $Find, $Replace

            $Find = [RegEx]::Escape(("'br/public:avm/{0}/{1}:{2}'" -f $ModuleType, $Ref.Name, $RefVersion))
            $Replace = "'{0}packages/{1}{2}/main.bicep'" -f $RefRelativePath, $RefIpmHubName, $RefVersionAddition
            $FileContent = $FileContent -replace $Find, $Replace
          }
        }
      }

      $FileContent | Out-File -FilePath $Destination -Encoding "UTF8" -Force
    }
  }

  # Remove telemetry if found
  $MainBicepFile = Join-Path -Path $PackageFolder -ChildPath "main.bicep"
  Remove-TelemetryFromBicepFile -BicepFile $MainBicepFile

  # Set a version within the main bicep file.
  Add-AdditionalMetadataToBicepFile -BicepFile $MainBicepFile -Metadata @{ version = $AvmModule.Version; publishedOn = $AvmModule.PublishedOn }

  # Copy additional files, and make some pre-defined changes
  "Found {0} additional files to copy..." -f $AdditionalFiles.Count | Write-Verbose
  ForEach($AdditionalFile in $AdditionalFiles)
  {
    $FileName = $AdditionalFile.DestinationName ?? (Split-Path -Path $AdditionalFile.Source -Leaf)
    $Destination = Join-Path $PackageFolder -ChildPath $AdditionalFile.RelativePath -AdditionalChildPath $FileName
    Copy-Item -Path $AdditionalFile.Source -Destination $Destination -Force | Out-Null
    $FileContent = Get-Content -Path $Destination -Encoding "UTF8"
    $FileContent = $FileContent -replace "#MODULENAME#", $AvmModule.Name
    $FileContent = $FileContent -replace "#MODULEACRNAME#", $AvmModule.AcrName
    $FileContent = $FileContent -replace "#MODULEACRTYPE#", $(If ($AvmModule.Classification -eq "ResourceModule") {"res"} ElseIf ($AvmModuleAVMType -eq "PatternModule") { "ptn" } Else { "utl" } )
    $FileContent = $FileContent -replace "#MODULEAZURETYPE#", $AvmModule.AzureType
    $FileContent = $FileContent -replace "#MODULEIPMHUBNAME#", $AvmModule.IpmHubName
    $FileContent = $FileContent -replace "#MODULEPUBLISHEDON#", $AvmModule.PublishedOn
    $FileContent | Set-Content -Path $Destination -Encoding "UTF8" -Force | Out-Null
  }

  # When referenced modules, create a ipmhub.json
  If ($AvmModule.ReferencedModules.Count -gt 0)
  {
    $Packages = $AvmModule.ReferencedModules | ForEach-Object {
      If ($_.Versions.Count -gt 1)
      {
        [Ordered] @{
          name = "{0}/{1}" -f $IpmHubOrganizationName, $_.IpmHubName
          downloadStrategy = "Multiple"
          versions = $_.Versions
        }
      } `
      Else
      {
        [Ordered] @{
          name = "{0}/{1}" -f $IpmHubOrganizationName, $_.IpmHubName
          version = $_.Versions | Select-Object -First 1
        }
      }
    }

    $IpmHubConfig = [Ordered] @{
      workingFolder = "packages"
      packages = [Array] ($Packages) ?? @()
    }

    $IpmHubConfigFile = Join-Path -Path $PackageFolder -ChildPath "ipmhub.json"
    Set-Content -Path $IpmHubConfigFile -Value ($IpmHubConfig | ConvertTo-Json -Depth 100) -Encoding "UTF8" -Force | Out-Null
  }
}

Function Get-AvmBicepPublishState
{
  [OutputType([PsCustomObject])]
  [CmdletBinding(DefaultParameterSetName = "SecureSasToken")]
  Param(
    [Parameter(Mandatory = $True, ParameterSetName = "SecureSasToken")]
    [ValidateNotNull()]
    [SecureString] $SecureSasToken,

    [Parameter(Mandatory = $True, ParameterSetName = "SasTokenFromEnvVariable")]
    [String] $SasTokenFromEnvironmentVariable,

    [Parameter(Mandatory = $True, ParameterSetName = "UnsecureSasToken")]
    [ValidateNotNullOrEmpty()]
    [String] $SasToken,

    [Parameter(Mandatory = $False)]
    [ValidateNotNullOrEmpty()]
    [String] $StateAccount = "ipmhubsponstor01weust",

    [Parameter(Mandatory = $False)]
    [ValidateNotNullOrEmpty()]
    [String] $StateTableName = "avmpublishstate",

    [Parameter(Mandatory = $False)]
    [ValidateNotNullOrEmpty()]
    [String] $Variant = "avmbicep"
  )

  Begin
  {
    "{0} - START" -f $MyInvocation.MyCommand | Write-Verbose
  }

  Process
  {
    If ($PSCmdlet.ParameterSetName -eq "SasTokenFromEnvVariable")
    {
      $SasToken = [System.Environment]::GetEnvironmentVariable($SasTokenFromEnvironmentVariable)
    } `
    ElseIf ($PSCmdlet.ParameterSetName -eq "SecureSasToken")
    {
      $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureSasToken)
      $SasToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    }

    $BaseUri = "https://{0}.table.core.windows.net/" -f $StateAccount
    $PartitionKey = $Variant
    $Filter = "`$filter=PartitionKey eq '$PartitionKey'&`$orderby=RowKey desc&`$top=1"
    $Headers = @{
      "x-ms-date" = [DateTime]::UtcNow.ToString("R")
      "Accept" = "application/json;odata=nometadata"
    }

    If (-not $SasToken.StartsWith("?"))
    {
      $SasToken = "?{0}" -f $SasToken
    }

    $Response = Invoke-RestMethod -Uri ("{0}{1}{2}&" -f $BaseUri, $StateTableName, $SasToken, $Filter) -Method "Get" -Headers $Headers | Select-Object -ExpandProperty "value"
    $Response
  }

  End
  {
    "{0} - END" -f $MyInvocation.MyCommand | Write-Verbose
  }
}

Function Set-AvmBicepPublishState
{
  [CmdletBinding(DefaultParameterSetName = "SecureSasToken")]
  Param(
    [Parameter(Mandatory = $True, ParameterSetName = "SecureSasToken")]
    [ValidateNotNull()]
    [SecureString] $SecureSasToken,

    [Parameter(Mandatory = $True, ParameterSetName = "SasTokenFromEnvVariable")]
    [String] $SasTokenFromEnvironmentVariable,

    [Parameter(Mandatory = $True, ParameterSetName = "UnsecureSasToken")]
    [ValidateNotNullOrEmpty()]
    [String] $SasToken,

    [Parameter(Mandatory = $False)]
    [String] $FromCommitId = "",

    [Parameter(Mandatory = $True)]
    [String] $TilCommitId,

    [Parameter(Mandatory = $False)]
    [DateTime] $PublishedOn = [DateTime]::UtcNow,

    [Parameter(Mandatory = $False)]
    [ValidateNotNullOrEmpty()]
    [String] $StateAccount = "ipmhubsponstor01weust",

    [Parameter(Mandatory = $False)]
    [ValidateNotNullOrEmpty()]
    [String] $StateTableName = "avmpublishstate",

    [Parameter(Mandatory = $False)]
    [ValidateNotNullOrEmpty()]
    [String] $Variant = "avmbicep"
  )

  Begin
  {
    "{0} - START" -f $MyInvocation.MyCommand | Write-Verbose
  }

  Process
  {
    $PreviousValue = $Null
    If ($PSCmdlet.ParameterSetName -eq "SasTokenFromEnvVariable")
    {
      $PreviousValue = Get-AvmBicepPublishState `
        -SasTokenFromEnvironmentVariable $SasTokenFromEnvironmentVariable `
        -StateAccount $StateAccount `
        -StateTableName $StateTableName `
        -Variant $Variant `
        -Verbose:$VerbosePreference

      $SasToken = [System.Environment]::GetEnvironmentVariable($SasTokenFromEnvironmentVariable)
    } `
    ElseIf ($PSCmdlet.ParameterSetName -eq "SecureSasToken")
    {
      $PreviousValue = Get-AvmBicepPublishState `
        -SecureSasToken $SecureSasToken `
        -StateAccount $StateAccount `
        -StateTableName $StateTableName `
        -Variant $Variant `
        -Verbose:$VerbosePreference

      $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureSasToken)
      $SasToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    } `
    Else
    {
      $PreviousValue = Get-AvmBicepPublishState `
        -SasToken $SasToken `
        -StateAccount $StateAccount `
        -StateTableName $StateTableName `
        -Variant $Variant `
        -Verbose:$VerbosePreference
    }

    $BaseUri = "https://{0}.table.core.windows.net/" -f $StateAccount
    $Record = @{
      PartitionKey = $Variant
      RowKey = "main"
      FromCommitId = $FromCommitId
      TilCommitId = $TilCommitId
      PublishedOn = $PublishedOn.ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
    } | ConvertTo-Json -Depth 10

    $Headers = @{
      "x-ms-date" = [DateTime]::UtcNow.ToString("R")
      "Accept" = "application/json;odata=nometadata"
      "Content-Type" = "application/json"
    }

    If (-not $SasToken.StartsWith("?"))
    {
      $SasToken = "?{0}" -f $SasToken
    }

    If ($Null -eq $PreviousValue)
    {
      $Response = Invoke-RestMethod -Uri ("{0}{1}{2}" -f $BaseUri, $StateTableName, $SasToken) -Method "Post" -Headers $Headers -Body $Record
    } `
    Else
    {
      $Response = Invoke-RestMethod -Uri ("{0}{1}(PartitionKey='{2}',RowKey='{3}'){4}" -f $BaseUri, $StateTableName, $Variant, "main", $SasToken) -Method "Merge" -Headers $Headers -Body $Record
    }

    $Response
  }

  End
  {
    "{0} - END" -f $MyInvocation.MyCommand | Write-Verbose
  }
}

Function Get-AvmBuildPublishSet
{
  [OutputType([PsCustomObject])]
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $True)]
    [String] $AvmPackageBuildRoot
  )

  # 01. Get information from the build folder
  $PackagesWithinBuildFolder = Get-ChildItem -Path $AvmPackageBuildRoot -Directory
  "Found {0} packages within the build folder." -f $PackagesWithinBuildFolder.Count | Write-Verbose

  $BuildResults = Get-Content -Path (Join-Path -Path $AvmPackageBuildRoot -ChildPath "results.json") -Encoding "UTF8" | ConvertFrom-Json -Depth 100
  $UniquePackages = [Array] ($BuildResults.Modules | ForEach-Object { [PsCustomObject] @{ Name = $_.IpmHubName; Description = $_.Description }}) ?? @()

  # 02. Traverse the build folder to look for packages to publish
  $ToPublish = Get-ChildItem -Path $AvmPackageBuildRoot -Recurse -Depth 1 | Where-Object { $_.Name -match "\d+\.\d+\.\d+" } | ForEach-Object {
    $ToPublishRoot = $_
    $Name = Split-Path -Path (Split-Path -Path $ToPublishRoot.FullName -Parent) -Leaf
    $IpmHubJsonPath = Join-Path -Path $ToPublishRoot.FullName -ChildPath "ipmhub.json"
    $DependsOn = @()
    If (Test-Path -Path $IpmHubJsonPath)
    {
      $IpmHubJsonObjPackages = Get-Content -Path $IpmHubJsonPath -Raw -Encoding "UTF8" | ConvertFrom-Json -Depth 10 | Select-Object -ExpandProperty "packages"
      ForEach($Package in $IpmHubJsonObjPackages)
      {
        $Versions = [Array] ($Package.versions ?? @($Package.version))
        ForEach($Version in $Versions)
        {
          $DependsOn += @{
            Name = $Package.name -replace "avm-bicep\/", ""
            Version = $Version
          }
        }
      }
    }

    [PsCustomObject] @{
      Name = $Name
      FullName = "avm-bicep/{0}" -f $Name
      Version = Split-Path -Path $_.FullName -Leaf
      Path = $ToPublishRoot.FullName
      DependsOn = $DependsOn
      PublicationOrder = 0
      Description = $UniquePackages | Where-Object { $_.Name -eq $Name } | Select-Object -First 1 -ExpandProperty "Description"
    }
  }

  # 03. Define our publication order
  $PubOrder = @()
  $PubIndex = 1
  $ModulesToDo = [System.Collections.Queue]::new()
  $ToPublish | Where-Object { $_.DependsOn.Count -eq 0 } | ForEach-Object { $_.PublicationOrder = $PubIndex++; $PubOrder += $_ }
  $ToPublish | Where-Object { $_.DependsOn.Count -gt 0 } | ForEach-Object { $ModulesToDo.Enqueue($_) }

  While ($ModulesToDo.Count -gt 0)
  {
    $Module = $ModulesToDo.Dequeue()
    $AllPresent = $True
    ForEach($Dep in $Module.DependsOn)
    {
      $InList = $PubOrder | Where-Object { $_.Name -eq $Dep.Name -and $_.Version -eq $Dep.Version }
      If ($Null -eq $Inlist)
      {
        $AllPresent = $False
      }
    }

    If ($AllPresent)
    {
      $Module.PublicationOrder = $PubIndex++
      $PubOrder += $Module
    } `
    Else
    {
      # Put back on queue
      $ModulesToDo.Enqueue($Module)
    }
  }

  # 04. Append nested packages information to our subset of unique pages, if required.
  $PackageNamesMissing = $ToPublish.Name | Where-Object { $UniquePackages.Name -notcontains $_ } | Select-Object -Unique
  $PackageNamesMissing | ForEach-Object {
    $UniquePackages += [PsCustomObject] @{ Name = $_; Description = "" }
  }

  [PsCustomObject] @{
    Packages = $PubOrder
    UniquePackages = $UniquePackages
  }
}

Function Invoke-IpmHubPackageEnsurance
{
  [OutputType([PsCustomObject[]])]
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $True)]
    [PsCustomObject[]] $Packages,

    [Parameter(Mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [String] $PackageCreationApi
  )

  Begin
  {
    "{0} - START" -f $MyInvocation.MyCommand | Write-Verbose
  }

  Process
  {
    $PackageData = [Array] ($Packages | ForEach-Object {
      @{
        packageName = $_.Name
        description = ($_.Description ?? "").Replace("This module deploys", "This Bicep AVM module deploys")
        descriptionLang = "en"
        projectUri = "https://ipmhub.io/avm-bicep"
      }
    }) ?? @()

    $Headers = @{ "Content-Type" = "application/json" }
    $Payload = @{ packages = $PackageData } | ConvertTo-Json -Depth 10

    $Response = Invoke-RestMethod -Uri $PackageCreationApi -Method "Post" -Headers $Headers -Body $Payload
    $Response
  }

  End
  {
    "{0} - END" -f $MyInvocation.MyCommand | Write-Verbose
  }
}

Function Send-MicrosoftTeamsChannelMessage
{
  <#
  .SYNOPSIS
    Sends a message to a Microsoft teams channel.

  .DESCRIPTION
    This PowerShell script posts a message to the Teams API by specifying a webhook.

  .PARAMETER TeamsWebhookUri
    The full uri to the MS teams webhook of the channel.

  .PARAMETER Text
    The text to send.

  .PARAMETER Title
    Optional: The titel of the message

  .PARAMETER MessageType
    Optional: The type of the message

  .PARAMETER ActivityTitle
    Optional: A sub-heading for sectioning off the message into parts.

	.PARAMETER ActivitySubTitle
	  Optional: A sub-title under activityTitle for further detail.

  .PARAMETER DetailTitle
    Optional: A string value that serves as a header describing any details you may include.

  .PARAMETER Details
	  Optional: An array of hashtables to display key pairs of names and values. Use this to display specific technical information if required.

  .INPUTS
    None. You cannot pipe objects to this file.

  .OUTPUTS
    String - Token of teams channel.

  .EXAMPLE
    PS> Send-IpmHubTeamsMessage

  #>
  [CmdletBinding()]
  Param (
    [Parameter(Mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [String] $TeamsWebhookUri,

    [Parameter(Mandatory=$False)]
    [ValidateNotNullOrEmpty()]
    [String] $Title = "Status",

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [String] $Text,

    [ValidateNotNullOrEmpty()]
    [ValidateSet("Information", "Success", "Warning", "Critical")]
    [String] $MessageType = "Information",

    [Parameter(Mandatory = $False)]
    [String] $ActivityTitle = "",

    [Parameter(Mandatory = $False)]
    [String] $ActivitySubTitle = "",

    [Parameter(Mandatory = $False)]
    [String] $DetailTitle = "",

    [Parameter(Mandatory = $False)]
    [HashTable[]] $Details
  )

  Function Send-TeamChannelMessage
  {
    Param (
      [Parameter(Mandatory = $true)]
      [ValidateSet("Information", "Success", "Warning", "Critical")]
      [string]$messageType,
      [Parameter(Mandatory = $true)]
      [string]$messageTitle,
      [Parameter(Mandatory = $true, ParameterSetName="SetBody")]
      [string]$messageBody,
      [Parameter(Mandatory = $true,	ParameterSetName="SetSummary")]
      [string]$messageSummary,
      [string]$activityTitle,
      [string]$activitySubtitle,
      [HashTable[]]$details = $null,
      [string]$detailTitle,
      [array]$buttons = $null,
      [Parameter(Mandatory = $true)]
      [string]$URI
    )

    Function Escape-JSONString($str){
      if ($str -eq $null) {return ""}
      $str = $str.ToString().Replace('"','\"').Replace('\','\\').Replace("`n",'\n\n').Replace("`r",'').Replace("`t",'\t')
      return $str
    }

    $imgInformation = "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"
    If ($messageSummary) {
      $TextOrSummary = 'summary'
      $TextOrSummaryContents = $messageSummary
    }

    $potentialActions = @()

    foreach ($button in $buttons)
    {
      $potentialActions += @{
        '@context' = 'http://schema.org'
        '@type'    = 'ViewAction'
        name	   = $($button.Name)
        target	 = @("$($button.Value)")
      }
    }
    $TextOrSummaryContents = Escape-JSONString $($TextOrSummaryContents)
    $body = ConvertTo-Json -Depth 6 @{
      title    			= "$($messageTitle)"
      $($TextOrSummary)	= [System.Text.RegularExpressions.Regex]::Unescape($($TextOrSummaryContents))
      sections = @(
        @{
          activityTitle    = "$($activityTitle)"
          activitySubtitle = "$activitySubtitle"
          activityImage    = "data:image/png;base64,$image"
        },
        @{
          title = $detailTitle
          facts = $details
          potentialAction = @(
            $potentialActions
          )
        }
      )
    }

    Invoke-RestMethod -Uri $uri -Method Post -body $body -UseBasicParsing -ContentType 'application/json'
  }

  Try
  {
    Send-TeamChannelMessage `
      -MessageType $MessageType `
      -MessageTitle $Title `
      -MessageBody $Text `
      -ActivityTitle $ActivityTitle `
      -ActivitySubtitle $ActivitySubTitle `
      -detailTitle $DetailTitle `
      -details $Details `
      -URI $TeamsWebhookUri `
      -ErrorAction Stop | Out-Null
  }
  Catch
  {
    Write-Error "Error occurred when sending message to MS Teams."
  }
}

Export-ModuleMember -Function "Get-AvmGitRepositoryCurrentBranchOrTagName"
Export-ModuleMember -Function "Get-AvmClassificationFromName"
Export-ModuleMember -Function "Get-GitAvmLastCommitId"
Export-ModuleMember -Function "Get-AvmGitFutureCommitsWithTags"
Export-ModuleMember -Function "Get-AvmGitRepositoryPublishedModules"
Export-ModuleMember -Function "Search-PublicRegistryModuleReference"
Export-ModuleMember -Function "Search-RelevantModuleFiles"
Export-ModuleMember -Function "Convert-AvmModuleMetadataItemsToFlat"
Export-ModuleMember -Function "Get-AvmModuleMetadata"
Export-ModuleMember -Function "Copy-AvmModuleForBuild"
Export-ModuleMember -Function "Get-AvmBicepPublishState"
Export-ModuleMember -Function "Set-AvmBicepPublishState"
Export-ModuleMember -Function "Get-AvmBuildPublishSet"
Export-ModuleMember -Function "Invoke-IpmHubPackageEnsurance"
Export-ModuleMember -Function "Send-MicrosoftTeamsChannelMessage"