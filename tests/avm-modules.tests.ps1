Param(
  [Parameter(Mandatory = $True)]
  [String] $PackagesRootPath
)

BeforeAll {
}

BeforeDiscovery {
  $Script:TestCases = @()
  $BicepFiles = Get-ChildItem -Path $PackagesRootPath -Recurse -Depth 2 | Where-Object { $_.Extension -in ".bicep" } | Sort-Object -Property $_.Directory
  $BicepFiles | ForEach-Object {
    $Script:TestCases += [HashTable] @{
      Name = $_.Name
      RelativePath = ($_.FullName -replace [RegEx]::Escape($PackagesRootPath + "\"), "") -replace [RegEx]::Escape($PackagesRootPath + "/"), ""
      Version = Split-Path -Path (Split-Path -Path $_.FullName -Parent) -Leaf
      FullName = $_.FullName
    }
  }
}

Describe 'Runtime BICEP tests' {
  BeforeAll {
  }

  It 'Syntax modifications of <relativePath> is complete' -ForEach $Script:TestCases {
    # All bicep files should have a 'version' metadata property with a semantic version, and a publishedOn date.
    # Also, telemetry should be disabled.
    $Script:ShouldBeVersion = $Version
    $Script:VersionFound = $False
    $Script:PublishedOnFound = $False
    $Script:TelemetryParameterFound = $False
    $Script:BicepContent = Get-Content -Path $FullName -Encoding "UTF8"

    ForEach($Line in $BicepContent)
    {
      # Is it a version line?
      If ($Line -match "metadata version\s*=\s*'(?<version>\d+\.\d+\.\d+)'")
      {
        $Script:VersionFound = $True
        $Matches['version'] | Should -Be $ShouldBeVersion
      }

      # It it a publishedOn line?
      If ($Line -match "metadata publishedOn\s*=\s*'(?<publishedOn>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)'")
      {
        $Script:PublishedOnFound = $True
      }

      # Is it the telemetry parameter?
      If ($Line -match "param\s*enableTelemetry\s*bool\s*=\s*(?<telemetryValue>false|true)")
      {
        $Script:TelemetryParameterFound = $True
        $Matches['telemetryValue'] | Should -Be "false"
      }

      # It contains a reference to a public registry module?
      If ($Line -like "*br/public:avm/*")
      {
        If ($Line -match "br/public:avm/(res|ptn|utl)/(.+):([0-9]{1,3}\.[0-9]{1,4}\.[0-9]{1,6})")
        {
          $Type = $Matches[1]
          $Name = $Matches[2]
          $Version = $Matches[3]
          Throw ("Found a reference to public registry module '{0}/{1}' version {2}." -f $Type, $Name, $Version)
        } `
        # When referring to a <version>, this occurs most of the time within a MD file for examples.
        ElseIf($Line -match "br/public:avm/(res|ptn|utl)/(.+):<version>")
        {
          $Type = $Matches[1]
          $Name = $Matches[2]
          $Version = "<version>"
          Throw ("Found a reference to public registry module '{0}/{1}'." -f $Type, $Name)
        }
      }
    }

    $Script:VersionFound | Should -Be $True
    $Script:PublishedOnFound | Should -Be $True
    $Script:TelemetryParameterFound | Should -Be $True
  }

  It '<relativePath> parses successfully' -ForEach $Script:TestCases {
    $Script:LintResults = $Null
    $Script:LintResults = & bicep lint "$($FullName)" 2>&1
    $LastExitCode | Should -Be 0
  }

  It 'Code of <relativePath> builds successfully' -ForEach $Script:TestCases {
    $Script:BicepRes = $Null
    $Script:BicepRes = ""
    $Script:BicepRes = & bicep build "$($FullName)" --stdout 2>&1
    $LastExitCode | Should -Be 0
    $Script:BicepRes | Should -Not -BeNullOrEmpty
    $Script:BicepRes.Count | Should -BeGreaterThan 10
  }
}


