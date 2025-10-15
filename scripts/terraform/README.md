# avm-tf-to-ipm-module Project

This project contains PowerShell modules for converting Azure Verified Modules (AVM) Terraform packages to IPM format.

## Directory Structure

```text
scripts/terraform/
├── avm-tf-to-ipm-module/           # Main PowerShell module
│   ├── public/                     # Public functions
│   │   ├── Convert-PackageName.ps1
│   │   ├── New-IpmPackageName.ps1
│   │   └── Write-Log.ps1
│   ├── avm-tf-to-ipm-module.psd1   # Module manifest
│   └── avm-tf-to-ipm-module.psm1   # Module file
├── settings.jsonc                  # Package name conversion settings
├── tests/                          # Test suite (Pester tests)
│   ├── *.Tests.ps1                 # Individual function tests
│   ├── Run-Tests.ps1               # Test runner
│   ├── PesterConfiguration.psd1    # Pester configuration
│   └── README-TESTS.md             # Test documentation
├── staging/                        # Build and staging area
└── logs/                           # Log files
```

## Quick Start

### Running the Module

```powershell
# Import the module
Import-Module .\avm-tf-to-ipm-module

# Convert a package name
$result = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-network-subnet"
# Returns: "network-subnet"
```

### Running Tests

```powershell
# Run all tests
cd tests
.\Run-Tests.ps1

# Run specific test
.\Run-Tests.ps1 -TestName "Convert-PackageName.Tests.ps1"

# Generate code coverage
.\Run-Tests.ps1 -CodeCoverage $true
```

### Validating Environment

```powershell
# Check if everything is set up correctly
cd tests
.\Validate-TestEnvironment.ps1
```

## Features

- **Package Name Conversion**: Transforms long Terraform package names using configurable mappings
- **IPM Name Generation**: Creates IPM-compatible package names from Terraform module names
- **Comprehensive Logging**: Structured logging with multiple levels and file output
- **Extensive Testing**: Full test suite with code coverage and CI/CD integration

## Configuration

Package name conversions are configured in `settings.jsonc`:

```json
{
  "nameReplacements": [
    {
      "search": "azurestackhci-virtualmachineinstance",
      "replacement": "azurestackhci-vm-instance"
    }
  ]
}
```

## Testing

The project includes comprehensive Pester tests with:

- ✅ Unit tests for all functions
- ✅ Parameter validation tests
- ✅ Error handling verification
- ✅ Code coverage reporting
- ✅ CI/CD integration support

See `tests/README-TESTS.md` for detailed testing documentation.

## Requirements

- PowerShell 5.1 or PowerShell 7+
- Pester 5.0+ (for testing)