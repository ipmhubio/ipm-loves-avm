BeforeAll {
    # Import the module under test
    $ModuleRoot = Join-Path $PSScriptRoot "../avm-tf-to-ipm-module"
    Import-Module -Name $ModuleRoot -Force
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
    }

    Context "When package name has existing conversion (integration test)" {
        It "Should use existing conversion for maintenance-maintenanceconfiguration" {
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-maintenance-maintenanceconfiguration"
            $result | Should -Be "maintenanceconfiguration"
        }

        It "Should use existing conversion for azurestackhci-virtualmachineinstance" {
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-azurestackhci-virtualmachineinstance"
            $result | Should -Be "azurestackhci-vm-instance"
        }
    }

    Context "When package name is 31-64 characters with no existing conversion" {
        It "Should use the name as-is when between 31-64 characters and no conversion exists" {
            # Create a 35-character name that doesn't exist in settings
            $mediumName = "some-very-long-package-name-here" # 34 characters
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$mediumName"
            $result | Should -Be $mediumName
        }
    }

    Context "When package name exceeds 64 characters" {
        It "Should throw exception for names longer than 64 characters with no conversion" {
            $veryLongName = "a" * 70 # 70 characters, exceeds limit
            { New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$veryLongName" } | Should -Throw "*is more than 64 characters and no conversion exists*"
        }
    }

    Context "Parameter validation" {
        It "Should require TerraformName parameter" {
            # Test that the function requires the mandatory parameter
            $function = Get-Command New-IpmPackageName
            $mandatoryParams = $function.Parameters.Values | Where-Object { $_.Attributes.Mandatory -eq $true }
            $mandatoryParams.Name | Should -Contain "TerraformName"
        }

        It "Should handle whitespace-only input" {
            $result = New-IpmPackageName -TerraformName "   "
            $result | Should -Be "   "
        }

        It "Should handle input with only prefix" {
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-"
            $result | Should -Be ""
        }

        It "Should handle multiple prefix removal correctly" {
            # Only the first matching prefix should be removed
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-test"
            $result | Should -Be "test"
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

        It "Should properly handle names exactly at the 31-character boundary" {
            # Test with name exactly 31 characters (triggers conversion check)
            $exactBoundaryName = "a" * 31
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$exactBoundaryName"
            # Since this exact name doesn't exist in conversions, it should return as-is
            $result | Should -Be $exactBoundaryName
        }
    }

    Context "Edge cases" {
        It "Should handle names with special characters" {
            $specialName = "test-module_with.special-chars"
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$specialName"
            $result | Should -Be $specialName
        }

        It "Should handle very long names that are exactly 64 characters" {
            $exactly64Name = "a" * 64
            $result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$exactly64Name"
            $result | Should -Be $exactly64Name
        }

        It "Should handle very long names that are 65 characters" {
            $exactly65Name = "a" * 65
            { New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-$exactly65Name" } | Should -Throw
        }
    }
}