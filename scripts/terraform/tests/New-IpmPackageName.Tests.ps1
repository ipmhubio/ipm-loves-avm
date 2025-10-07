BeforeAll {
    # Import the module under test
    $ModuleRoot = Join-Path $PSScriptRoot "../avm-tf-to-ipm-module"
    Import-Module -Name $ModuleRoot -Force

    # Mock Write-Log to avoid console output during tests
    Mock Write-Log {} -ModuleName "avm-tf-to-ipm-module"

    # Mock Convert-PackageName function to control its behavior in tests
    Mock Convert-PackageName -ModuleName "avm-tf-to-ipm-module" {
        param($PackageName)
        switch ($PackageName) {
            "maintenance-maintenanceconfiguration" { return "maintenanceconfiguration" }
            "azurestackhci-virtualmachineinstance" { return "azurestackhci-vm-instance" }
            "compute-proximityplacementgroup" { return "compute-prox-placement-group" }
            default { return $false }
        }
    }
}

Describe "New-IpmPackageName" -Tag "Unit" {
    Context "When removing standard Terraform prefixes" {
        It "Should remove 'terraform-azurerm-avm-res-' prefix" {
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-network-subnet"
            $result | Should -Be "network-subnet"
        }

        It "Should remove 'terraform-avm-azurerm-res-' prefix" {
            $result = New-IpmPackageName -TerraformName "terraform-avm-azurerm-res-compute-vm"
            $result | Should -Be "compute-vm"
        }

        It "Should handle names without standard prefixes" {
            $result = New-IpmPackageName -TerraformName "custom-module-name"
            $result | Should -Be "custom-module-name"
        }
    }

    Context "When package name is 30 characters or less" {
        It "Should return the name as-is when under 30 characters" {
            $shortName = "short-name" # 10 characters
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$shortName"
            $result | Should -Be $shortName
        }

        It "Should return the name as-is when exactly 30 characters" {
            $exactName = "a" * 30 # Exactly 30 characters
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$exactName"
            $result | Should -Be $exactName
        }

        It "Should not call Convert-PackageName for names 30 characters or less" {
            $shortName = "short-name"
            New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$shortName"
            Should -Not -Invoke Convert-PackageName -ModuleName "avm-tf-to-ipm-module"
        }
    }

    Context "When package name is longer than 30 characters but has existing conversion" {
        It "Should use existing conversion for known long names" {
            $longName = "maintenance-maintenanceconfiguration" # 35 characters
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$longName"
            $result | Should -Be "maintenanceconfiguration"

            Should -Invoke Convert-PackageName -ParameterFilter { $PackageName -eq $longName } -ModuleName "avm-tf-to-ipm-module"
            Should -Invoke Write-Log -ParameterFilter {
                $Message -like "*Used existing conversion*" -and $Level -eq "INFO"
            } -ModuleName "avm-tf-to-ipm-module"
        }

        It "Should log the conversion when using existing mapping" {
            $longName = "azurestackhci-virtualmachineinstance" # 35 characters
            New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$longName"

            Should -Invoke Write-Log -ParameterFilter {
                $Message -like "*Used existing conversion: Terraform name*azurestackhci-virtualmachineinstance*azurestackhci-vm-instance*" -and
                $Level -eq "INFO"
            } -ModuleName "avm-tf-to-ipm-module"
        }
    }

    Context "When package name is 31-64 characters with no existing conversion" {
        It "Should use the name as-is when between 31-64 characters and no conversion exists" {
            $mediumName = "a" * 35 # 35 characters, no existing conversion
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$mediumName"
            $result | Should -Be $mediumName

            Should -Invoke Convert-PackageName -ParameterFilter { $PackageName -eq $mediumName }
            Should -Invoke Write-Log -ParameterFilter {
                $Message -like "*is between 30-64 characters, using as-is*" -and $Level -eq "INFO"
            }
        }

        It "Should log when using name as-is for 31-64 character names" {
            $mediumName = "some-very-long-package-name-here" # 34 characters
            New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$mediumName"

            Should -Invoke Write-Log -ParameterFilter {
                $Message -like "*is between 30-64 characters, using as-is since no existing conversion found*" -and
                $Level -eq "INFO"
            }
        }
    }

    Context "When package name exceeds 64 characters" {
        It "Should throw exception for names longer than 64 characters with no conversion" {
            $veryLongName = "a" * 70 # 70 characters, exceeds limit
            { New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$veryLongName" } | Should -Throw "*is more than 64 characters and no conversion exists*"

            Should -Invoke Convert-PackageName -ParameterFilter { $PackageName -eq $veryLongName }
            Should -Invoke Write-Log -ParameterFilter {
                $Message -like "*is more than 64 characters and no conversion exists*" -and $Level -eq "ERROR"
            }
        }

        It "Should use conversion for names longer than 64 characters when conversion exists" {
            # Mock a very long name that has a conversion
            Mock Convert-PackageName {
                param($PackageName)
                if ($PackageName -eq ("very-long-package-name-" * 4)) { # Creates a very long string
                    return "short-converted-name"
                }
                return $false
            }

            $veryLongName = "very-long-package-name-" * 4 # Creates a string > 64 chars
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$veryLongName"
            $result | Should -Be "short-converted-name"
        }
    }

    Context "Parameter validation and edge cases" {
        It "Should require TerraformName parameter" {
            { New-IpmPackageName } | Should -Throw
        }

        It "Should handle empty string input" {
            $result = New-IpmPackageName -TerraformName ""
            $result | Should -Be ""
        }

        It "Should handle whitespace-only input" {
            $result = New-IpmPackageName -TerraformName "   "
            $result | Should -Be "   "
        }

        It "Should handle input with only prefix" {
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-"
            $result | Should -Be ""
        }

        It "Should handle multiple prefix patterns in same name" {
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-terraform-avm-azurerm-res-test"
            $result | Should -Be "terraform-avm-azurerm-res-test"
        }
    }

    Context "Real-world scenarios" {
        It "Should handle actual AVM module names correctly" -TestCases @(
            @{
                InputName = "terraform-azurerm-avm-res-network-applicationgateway"
                Expected = "network-applicationgateway"
            },
            @{
                InputName = "terraform-azurerm-avm-res-compute-virtualmachine"
                Expected = "compute-virtualmachine"
            },
            @{
                InputName = "terraform-azurerm-avm-res-storage-storageaccount"
                Expected = "storage-storageaccount"
            }
        ) {
            param($InputName, $Expected)
            $result = New-IpmPackageName -TerraformName $InputName
            $result | Should -Be $Expected
        }

        It "Should properly check for conversions when name length is exactly at boundary" {
            # Test with name exactly 31 characters (triggers conversion check)
            $exactBoundaryName = "a" * 31
            New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$exactBoundaryName"
            Should -Invoke Convert-PackageName -ParameterFilter { $PackageName -eq $exactBoundaryName }
        }
    }

    Context "Logging behavior" {
        It "Should log when checking for existing conversion" {
            $longName = "a" * 35
            New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$longName"

            Should -Invoke Write-Log -ParameterFilter {
                $Message -like "*is more than 30 characters. Checking for existing conversion*" -and
                $Level -eq "INFO"
            }
        }

        It "Should not log conversion messages for short names" {
            $shortName = "short"
            New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$shortName"

            Should -Not -Invoke Write-Log -ParameterFilter {
                $Message -like "*more than 30 characters*"
            }
        }
    }
}