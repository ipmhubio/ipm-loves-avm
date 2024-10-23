Param(
  [Parameter(Mandatory = $True)]
  [String] $PackagesRootPath
)

BeforeAll {
}

BeforeDiscovery {
  $Script:TestCases = @()
  $BicepFiles = Get-ChildItem -Path $PackagesRootPath -Recurse -Depth 2 | Where-Object { $_.Extension -in ".bicep" }
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

  It 'Syntax of <relativePath> is complete and parses successfully' -ForEach $Script:TestCases {
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
    }

    $Script:VersionFound | Should -Be $True
    $Script:PublishedOnFound | Should -Be $True
        
    $Script:LintResults = $Null
    { $Script:LintResults = & bicep lint "$($FullName)" 2>&1 } | Should -Not -Throw
  }

  It 'Code of <relativePath> builds successfully' -ForEach $Script:TestCases {
    $Script:BicepRes = $Null
    $Script:BicepRes = ""
    { $Script:BicepRes = & bicep build "$($FullName)" --stdout 2>&1 } | Should -Not -Throw
    $Script:BicepRes | Should -Not -BeNullOrEmpty
    $Script:BicepRes.Count | Should -BeGreaterThan 10
  }
}


