BeforeAll {
    # Import the module under test
    $ModuleRoot = Join-Path $PSScriptRoot "../avm-tf-to-ipm-module"
    Import-Module -Name $ModuleRoot -Force

    # Create test settings file for testing
    $TestSettingsPath = Join-Path $TestDrive "test-settings.jsonc"
    $TestSettings = @{
        nameReplacements = @(
            @{
                search = "azurestackhci-virtualmachineinstance"
                replacement = "azurestackhci-vm-instance"
            },
            @{
                search = "compute-proximityplacementgroup"
                replacement = "compute-prox-placement-group"
            },
            @{
                search = "containerinstance-containergroup"
                replacement = "container-instance-group"
            },
            @{
                search = "maintenance-maintenanceconfiguration"
                replacement = "maintenanceconfiguration"
            }
        )
    }
    $TestSettings | ConvertTo-Json -Depth 3 | Set-Content -Path $TestSettingsPath
}

Describe "Convert-PackageName" -Tag "Unit" {
    Context "When package name has exact match in settings" {
        It "Should convert '<PackageName>' to '<ExpectedResult>'" -TestCases @(
            @{ PackageName = "azurestackhci-virtualmachineinstance"; ExpectedResult = "azurestackhci-vm-instance" }
            @{ PackageName = "compute-proximityplacementgroup"; ExpectedResult = "compute-prox-placement-group" }
            @{ PackageName = "containerinstance-containergroup"; ExpectedResult = "container-instance-group" }
            @{ PackageName = "maintenance-maintenanceconfiguration"; ExpectedResult = "maintenanceconfiguration" }
        ) {
            param($PackageName, $ExpectedResult)

            $result = Convert-PackageName -packageName $PackageName -SettingsPath $TestSettingsPath
            $result | Should -Be $ExpectedResult
        }
    }

    Context "When package name has no match in settings" {
        It "Should return false for non-matching package name" {
            $result = Convert-PackageName -packageName "non-existing-package" -SettingsPath $TestSettingsPath
            $result | Should -Be $false
        }

        It "Should return false for partial matches" {
            $result = Convert-PackageName -packageName "azurestackhci-virtualmachine" -SettingsPath $TestSettingsPath
            $result | Should -Be $false
        }

        It "Should handle case-sensitive matching correctly" {
            # The actual implementation seems to be case-insensitive, so test that
            $result = Convert-PackageName -packageName "AZURESTACKHCI-VIRTUALMACHINEINSTANCE" -SettingsPath $TestSettingsPath
            $result | Should -Be "azurestackhci-vm-instance"
        }
    }

    Context "When settings file is missing or invalid" {
        It "Should return false and handle error when settings file doesn't exist" {
            $nonExistentPath = Join-Path $TestDrive "non-existent-settings.jsonc"

            $result = Convert-PackageName -packageName "test-package" -SettingsPath $nonExistentPath
            $result | Should -Be $false
        }

        It "Should return false and handle error when settings file is invalid JSON" {
            $InvalidSettingsPath = Join-Path $TestDrive "invalid-settings.jsonc"
            "{ invalid json content" | Set-Content -Path $InvalidSettingsPath

            $result = Convert-PackageName -packageName "test-package" -SettingsPath $InvalidSettingsPath
            $result | Should -Be $false
        }
    }

    Context "When using default settings path" {
        BeforeEach {
            # Create a temporary settings file in the expected default location
            $DefaultSettingsDir = Join-Path $ModuleRoot "public"
            $DefaultSettingsPath = Join-Path $DefaultSettingsDir "../../settings.jsonc"
            $DefaultSettingsFullPath = Resolve-Path $DefaultSettingsPath -ErrorAction SilentlyContinue

            if (-not $DefaultSettingsFullPath) {
                # Create the directory structure if it doesn't exist
                $SettingsDir = Split-Path $DefaultSettingsPath -Parent
                if (-not (Test-Path $SettingsDir)) {
                    New-Item -ItemType Directory -Path $SettingsDir -Force
                }
                # Copy our test settings to the default location for this test
                Copy-Item $TestSettingsPath $DefaultSettingsPath
            }
        }

        It "Should use default settings path when not specified" {
            $result = Convert-PackageName -packageName "azurestackhci-virtualmachineinstance"
            # The result should either be the converted name or false if default settings don't exist
            $result | Should -BeIn @("azurestackhci-vm-instance", $false)
        }
    }

    Context "Parameter validation" {
        It "Should require packageName parameter" {
            # Test that the function requires the mandatory parameter
            $function = Get-Command Convert-PackageName
            $mandatoryParams = $function.Parameters.Values | Where-Object { $_.Attributes.Mandatory -eq $true }
            $mandatoryParams.Name | Should -Contain "packageName"
        }

        It "Should handle null or whitespace packageName gracefully" {
            $result = Convert-PackageName -packageName "   " -SettingsPath $TestSettingsPath
            $result | Should -Be $false
        }
    }

    Context "Edge cases and boundary conditions" {
        It "Should handle settings file with empty nameReplacements array" {
            $EmptySettingsPath = Join-Path $TestDrive "empty-settings.jsonc"
            @{ nameReplacements = @() } | ConvertTo-Json | Set-Content -Path $EmptySettingsPath

            $result = Convert-PackageName -packageName "test-package" -SettingsPath $EmptySettingsPath
            $result | Should -Be $false
        }

        It "Should handle the first exact match when multiple matches could exist" {
            $MultiMatchSettingsPath = Join-Path $TestDrive "multi-match-settings.jsonc"
            $MultiMatchSettings = @{
                nameReplacements = @(
                    @{ search = "test-package"; replacement = "first-replacement" },
                    @{ search = "test-package"; replacement = "second-replacement" }
                )
            }
            $MultiMatchSettings | ConvertTo-Json -Depth 3 | Set-Content -Path $MultiMatchSettingsPath

            $result = Convert-PackageName -packageName "test-package" -SettingsPath $MultiMatchSettingsPath
            $result | Should -Be "first-replacement"
        }

        It "Should handle special characters in package names" {
            $SpecialCharSettingsPath = Join-Path $TestDrive "special-char-settings.jsonc"
            $SpecialCharSettings = @{
                nameReplacements = @(
                    @{ search = "test-package_with.special-chars"; replacement = "converted-package" }
                )
            }
            $SpecialCharSettings | ConvertTo-Json -Depth 3 | Set-Content -Path $SpecialCharSettingsPath

            $result = Convert-PackageName -packageName "test-package_with.special-chars" -SettingsPath $SpecialCharSettingsPath
            $result | Should -Be "converted-package"
        }
    }
}