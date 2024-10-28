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
    [String[]] $FilterByPublicName
  )

  $AvmResFolderRoot = Join-Path $AvmRootFolder -ChildPath "res"
  # $AvmPtnFolderRoot = Join-Path $AvmRootFolder -ChildPath "ptn"
  $AvmUtlFolderRoot = Join-Path $AvmRootFolder -ChildPath "utl"

  # 01. We first need to gather the list of published AVM modules from the current branch
  $AvmPublishedModuleListLatest = Get-AvmGitRepositoryPublishedModules -ResourceModules -UtilityModules | Where-Object { $True -eq $_.IsLatest } | Select-Object -ExcludeProperty "IsLatest"

  # TODO: This list should be in a json configuration / mapping file.
  $IpmHubNameReplacements = @(
    @{
      Search = "azure-virtual-desktop"
      Replace = "avd"
    }
    @{
      Search = "azure-active-directory"
      Replace ="aad"
    }
    @{
      Search = "azure-"
      Replace = ""
    }
    @{
      Search = "kubernetes-service"
      Replace = ""
    }
    @{
      Search = "-configuration-"
      Replace = "-config-"
    }
    @{
      Search = "kubernetes-config-flux-configurations"
      Replace = "kubernetes-flux-configurations"
    }
    @{
      Search = "application-"
      Replace = "app-"
    }
    @{
      Search = "web-app-firewall"
      Replace = "waf"
    }
    @{
      Search = "cosmos-db-mongodb-vcore-cluster"
      Replace = "cosmos-db-for-mongodb"
    }
    @{
      Search = "dbforpostgresql-flexible-servers"
      Replace ="postgre-sql-flex-server"
    }
    @{
      Search = "container-instances-container-groups"
      Replace = "container-instance"
    }
    @{
      Search = "machine-learning-services-workspaces"
      Replace = "machine-learning-workspace"
    }
    @{
      Search = "operations-management-solutions"
      Replace = "ops-management-solution"
    }
    @{
      Search = "virtual-machine-image-templates"
      Replace = "vm-image-templates"
    }
    @{
      Search = "virtual-network-gateway-connections"
      Replace = "vnet-gateway-connections"
    }
    @{
      Search = "default-interface-types-for-avm-modules"
      Replace = "common-types"
    }
    @{
      Search = "diagnostic-settings-activity-logs-for-subscriptions"
      Replace = "insights-diagnostic-setting"
    }
    @{
      Search = "app-insights-linked-storage-account"
      Replace = "insights-collection-endpoint"
    }
  )

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

    # Extact our description from the BICEP file. We have 2 variants, single line and multiline.
    $Description = ($BicepFileContent | Where-Object { $_ -like "metadata description =*" } | Select-Object -First 1) -replace "metadata\s*description\s*=\s*", ""
    If ($Description -eq "'''") # Multiline
    {
      # TODO: Support multiline descriptions (for now, only found within the utl types)
      $Description = ""
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
      $ModuleToAdd.IpmHubName = $ModuleToAdd.IpmHubName -replace $Replacement.Search, $Replacement.Replace
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
    [HashTable[]] $AdditionalFiles
  )

  If ($AvmModule.IpmHubName.Length -gt 30)
  {
    "Cannot build package '{0}'. Its name size exceeds 30 characters. AVM name: '{1}'." -f $AvmModule.IpmHubName, $AvmModule.AcrName | Write-Warning
    Return
  }

  # If the version only contains a major and minor, there is something wrong.
  If (($AvmModule.Version -split "\.").Count -ne 3)
  {
    $VersionValue = $AvmModule.Version | ConvertTo-Json -Depth 2
    "Cannot build package '{0}'. No published version found. AVM name: '{1}', version value: '{2}'." -f $AvmModule.IpmHubName, $AvmModule.AcrName, $VersionValue | Write-Warning
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
      ForEach($Ref in $Item.ReferencedModules)
      {
        $RefIpmHubName = $AvmModule.ReferencedModules | Where-Object { $_.Name -eq $Ref.Name } | Select-Object -First 1 -ExpandProperty "IpmHubName"
        $RefRelativePath = "{0}/" -f ((Split-Path -Path $Item.RelativePath -Parent) -split "[/\\]" | Where-Object { $_ -ne "" } | ForEach-Object { ".." }) -join [System.IO.Path]::DirectorySeparatorChar
        If ($RefRelativePath.Length -eq 1)
        {
          $RefRelativePath = ".{0}" -f $RefRelativePath
        }

        # | `br/public:avm/res/network/private-endpoint:0.7.0` | Remote reference |
        $ModuleTypes = @("res", "ptn", "utl")
        ForEach($ModuleType in $ModuleTypes)
        {
          $FileContent = $FileContent -replace ("br/public:avm/{0}/{1}:<version>" -f $ModuleType, $Ref.Name), ("./packages/{0}/main.bicep" -f $AvmModule.IpmHubName)
        }

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

Export-ModuleMember -Function "Get-AvmGitRepositoryCurrentBranchOrTagName"
Export-ModuleMember -Function "Get-AvmClassificationFromName"
Export-ModuleMember -Function "Get-AvmGitFutureCommitsWithTags"
Export-ModuleMember -Function "Get-AvmGitRepositoryPublishedModules"
Export-ModuleMember -Function "Search-PublicRegistryModuleReference"
Export-ModuleMember -Function "Search-RelevantModuleFiles"
Export-ModuleMember -Function "Convert-AvmModuleMetadataItemsToFlat"
Export-ModuleMember -Function "Get-AvmModuleMetadata"
Export-ModuleMember -Function "Copy-AvmModuleForBuild"
