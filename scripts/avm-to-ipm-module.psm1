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

  # 01. We first need to gather the list of published AVM modules from the current branch
  $AvmPublishedModuleListLatest = Get-AvmGitRepositoryPublishedModules -ResourceModules -UtilityModules | Where-Object { $True -eq $_.IsLatest } | Select-Object -ExcludeProperty "IsLatest"

  $Modules = [System.Collections.ArrayList]@()
  $Modules.Clear()

  # We always retrieve all  modules, because there can be references. We should filter them out at the end if needed.
  $VersionFiles = @(
    Get-ChildItem -Path $AvmUtlFolderRoot -Filter "version.json" -Recurse
    Get-ChildItem -Path $AvmResfolderRoot -Filter "version.json" -Recurse
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
        ForEach($RefVersion in $Ref.Versions)
        {
          ForEach($ModuleType in ($ModuleTypes))
          {
            $Find = [RegEx]::Escape(("``br/public:avm/{0}/{1}:{2}`` | Remote Reference |" -f $ModuleType, $Ref.Name, $RefVersion))
            $Replace = "``{0}packages/{1}/main.bicep`` | Local Reference |" -f $RefRelativePath, $RefIpmHubName
            $FileContent = $FileContent -replace $Find, $Replace

            $Find = [RegEx]::Escape(("'br/public:avm/{0}/{1}:{2}'" -f $ModuleType, $Ref.Name, $RefVersion))
            $Replace = "'{0}packages/{1}/main.bicep'" -f $RefRelativePath, $RefIpmHubName
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
        @{
          name = "{0}/{1}" -f $IpmHubOrganizationName, $_.IpmHubName
          strategy = "Multiple"
          versions = $_.Versions
        }
      } `
      Else
      {
        @{
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
  $UniquePackages = $BuildResults.Modules | ForEach-Object { [PsCustomObject] @{ Name = $_.IpmHubName; Description = $_.Description }}

  # 02. Traverse the build folder to look for packages to publish
  $ToPublish = Get-ChildItem -Path $AvmPackageBuildRoot -Recurse -Depth 1 | Where-Object { $_.Name -match "\d\.\d\.\d" } | ForEach-Object {
    $Name = Split-Path -Path (Split-Path -Path $_.FullName -Parent) -Leaf
    $IpmHubJsonPath = Join-Path -Path $_.FullName -ChildPath "ipmhub.json"
    $DependsOn = @()
    If (Test-Path -Path $IpmHubJsonPath)
    {
      $DependsOn = Get-Content -Path $IpmHubJsonPath -Raw -Encoding "UTF8" | ConvertFrom-Json -Depth 10 | Select-Object -ExpandProperty "packages" | ForEach-Object {
        @{
          Name = $_.name -replace "avm-bicep\/", ""
          Version = $_.version
        }
      }
    }

    [PsCustomObject] @{
      Name = $Name
      FullName = "avm-bicep/{0}" -f $Name
      Version = Split-Path -Path $_.FullName -Leaf
      Path = $_.FullName
      DependsOn = $DependsOn
      PublicationOrder = 0
      Description = $UniqueModules | Where-Object { $_.Name -eq $Name } | Select-Object -First 1 -ExpandProperty "Description"
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
    $imgSuccess = "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"
    $imgCritical = "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"
    $imgWarning = "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"

    Switch ($messageType)
    {
      { $_ -eq "Information" } { $notify = $true; $titleColor = "blue"; $image = $imgCritical }
      { $_ -eq "Success" } { $notify = $true; $titleColor = "green"; $image = $imgSuccess }
      { $_ -eq "Warning" } { $notify = $true; $titleColor = "orange"; $image = $imgWarning }
      { $_ -eq "Critical" } { $notify = $true; $titleColor = "red"; $image = $imgInformation }
    }

    If ($messageBody) {
      $TextOrSummary = 'text'
      $TextOrSummaryContents = $messageBody
    }
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