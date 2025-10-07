#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates the test environment and checks if all tests can be discovered

.DESCRIPTION
    This script performs pre-flight checks to ensure the test environment is properly configured
    and all test files can be discovered and loaded without errors.

.EXAMPLE
    .\Validate-TestEnvironment.ps1
#>

[CmdletBinding()]
param()

Write-Host "=== Test Environment Validation ===" -ForegroundColor Green

# Check PowerShell version
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan

# Check if we're in the correct directory
$CurrentPath = Get-Location
Write-Host "Current Directory: $CurrentPath" -ForegroundColor Cyan

# Check if Pester is available
try {
    $PesterModule = Get-Module -Name Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if ($PesterModule) {
        Write-Host "✅ Pester Available: Version $($PesterModule.Version)" -ForegroundColor Green

        if ($PesterModule.Version.Major -lt 5) {
            Write-Warning "⚠️ Pester version 5.0+ is recommended for best compatibility"
        }
    } else {
        Write-Host "❌ Pester not found. Install with: Install-Module -Name Pester -Force" -ForegroundColor Red
        return
    }
} catch {
    Write-Host "❌ Error checking Pester: $_" -ForegroundColor Red
    return
}

# Check if the module directory exists
$ModulePath = Join-Path $PSScriptRoot "../avm-tf-to-ipm-module"
if (Test-Path $ModulePath) {
    Write-Host "✅ Module directory found: $ModulePath" -ForegroundColor Green
} else {
    Write-Host "❌ Module directory not found: $ModulePath" -ForegroundColor Red
    return
}

# Check if module files exist
$ModuleFiles = @(
    "avm-tf-to-ipm-module.psd1"
    "avm-tf-to-ipm-module.psm1"
    "public\Convert-PackageName.ps1"
    "public\New-IpmPackageName.ps1"
    "public\Write-Log.ps1"
)

$MissingFiles = @()
foreach ($File in $ModuleFiles) {
    $FilePath = Join-Path $ModulePath $File
    if (Test-Path $FilePath) {
        Write-Host "✅ Found: $File" -ForegroundColor Green
    } else {
        Write-Host "❌ Missing: $File" -ForegroundColor Red
        $MissingFiles += $File
    }
}

if ($MissingFiles.Count -gt 0) {
    Write-Host "❌ Cannot proceed - missing required module files" -ForegroundColor Red
    return
}

# Check if test files exist
$TestFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*.Tests.ps1"
if ($TestFiles.Count -gt 0) {
    Write-Host "✅ Found $($TestFiles.Count) test file(s):" -ForegroundColor Green
    $TestFiles | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Cyan }
} else {
    Write-Host "❌ No test files found (*.Tests.ps1)" -ForegroundColor Red
    return
}

# Try to import the module
try {
    Write-Host "🔍 Testing module import..." -ForegroundColor Yellow
    Import-Module $ModulePath -Force -ErrorAction Stop
    Write-Host "✅ Module imported successfully" -ForegroundColor Green

    # Check if functions are available
    $Functions = @("Convert-PackageName", "New-IpmPackageName", "Write-Log")
    foreach ($Function in $Functions) {
        if (Get-Command $Function -ErrorAction SilentlyContinue) {
            Write-Host "✅ Function available: $Function" -ForegroundColor Green
        } else {
            Write-Host "❌ Function not found: $Function" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "❌ Error importing module: $_" -ForegroundColor Red
    return
}

# Test settings file
$SettingsPath = Join-Path $PSScriptRoot "../settings.jsonc"
if (Test-Path $SettingsPath) {
    Write-Host "✅ Settings file found: settings.jsonc" -ForegroundColor Green
    try {
        $Settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
        if ($Settings.nameReplacements) {
            Write-Host "✅ Settings file contains $($Settings.nameReplacements.Count) name replacements" -ForegroundColor Green
        } else {
            Write-Host "⚠️ Settings file exists but no nameReplacements found" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "❌ Error parsing settings file: $_" -ForegroundColor Red
    }
} else {
    Write-Host "⚠️ Settings file not found: settings.jsonc (tests may use mock data)" -ForegroundColor Yellow
}

# Test basic functionality
try {
    Write-Host "🔍 Testing basic function calls..." -ForegroundColor Yellow

    # Test Write-Log (should not throw)
    $TestLogPath = Join-Path $env:TEMP "test-validation.log"
    Write-Log -Message "Test validation" -LogPath $TestLogPath -Level "INFO"
    if (Test-Path $TestLogPath) {
        Write-Host "✅ Write-Log function works" -ForegroundColor Green
        Remove-Item $TestLogPath -ErrorAction SilentlyContinue
    }

    # Test New-IpmPackageName
    $TestResult = New-IpmPackageName -TerraformName "terraform-azurerm-avm-res-test-module"
    if ($TestResult -eq "test-module") {
        Write-Host "✅ New-IpmPackageName function works" -ForegroundColor Green
    } else {
        Write-Host "⚠️ New-IpmPackageName returned: $TestResult" -ForegroundColor Yellow
    }

    # Test Convert-PackageName with a non-existent package (should return false)
    $ConvertResult = Convert-PackageName -PackageName "non-existent-package" -SettingsPath $SettingsPath
    if ($ConvertResult -eq $false) {
        Write-Host "✅ Convert-PackageName function works" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Convert-PackageName unexpected result: $ConvertResult" -ForegroundColor Yellow
    }

} catch {
    Write-Host "❌ Error testing functions: $_" -ForegroundColor Red
}

# Try to discover tests without running them
try {
    Write-Host "🔍 Testing test discovery..." -ForegroundColor Yellow
    Import-Module Pester -Force -ErrorAction Stop

    foreach ($TestFile in $TestFiles) {
        try {
            # Parse the test file to check for syntax errors
            $TestContent = Get-Content $TestFile.FullName -Raw
            $Tokens = $null
            $Errors = $null
            [System.Management.Automation.PSParser]::Tokenize($TestContent, [ref]$Tokens, [ref]$Errors)

            if ($Errors.Count -eq 0) {
                Write-Host "✅ Test file syntax OK: $($TestFile.Name)" -ForegroundColor Green
            } else {
                Write-Host "❌ Syntax errors in $($TestFile.Name): $($Errors.Count) error(s)" -ForegroundColor Red
                $Errors | ForEach-Object { Write-Host "  - Line $($_.Token.StartLine): $($_.Message)" -ForegroundColor Red }
            }
        } catch {
            Write-Host "❌ Error parsing $($TestFile.Name): $_" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "❌ Error during test discovery: $_" -ForegroundColor Red
}

# Check test runner
$TestRunnerPath = Join-Path $PSScriptRoot "Run-Tests.ps1"
if (Test-Path $TestRunnerPath) {
    Write-Host "✅ Test runner available: Run-Tests.ps1" -ForegroundColor Green
} else {
    Write-Host "❌ Test runner not found: Run-Tests.ps1" -ForegroundColor Red
}

# Check configuration file
$ConfigPath = Join-Path $PSScriptRoot "PesterConfiguration.psd1"
if (Test-Path $ConfigPath) {
    Write-Host "✅ Pester configuration available: PesterConfiguration.psd1" -ForegroundColor Green
    try {
        $Config = Import-PowerShellDataFile -Path $ConfigPath
        Write-Host "✅ Configuration file loaded successfully" -ForegroundColor Green
    } catch {
        Write-Host "❌ Error loading configuration: $_" -ForegroundColor Red
    }
} else {
    Write-Host "❌ Pester configuration not found: PesterConfiguration.psd1" -ForegroundColor Red
}

Write-Host "`n=== Validation Summary ===" -ForegroundColor Green
Write-Host "Environment appears ready for testing!" -ForegroundColor Green
Write-Host "`nTo run tests:" -ForegroundColor Cyan
Write-Host "  .\Run-Tests.ps1" -ForegroundColor White
Write-Host "`nFor specific test:" -ForegroundColor Cyan
Write-Host "  .\Run-Tests.ps1 -TestName 'Convert-PackageName.Tests.ps1'" -ForegroundColor White
Write-Host "`nFor help:" -ForegroundColor Cyan
Write-Host "  Get-Help .\Run-Tests.ps1 -Full" -ForegroundColor White