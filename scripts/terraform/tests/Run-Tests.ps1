#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test runner script for avm-tf-to-ipm-module Pester tests

.DESCRIPTION
    This script runs all Pester tests for the avm-tf-to-ipm-module PowerShell module.
    It provides options for running specific test categories, generating code coverage,
    and outputting results in various formats.

.PARAMETER TestName
    Specify a specific test file or pattern to run (optional)

.PARAMETER Tag
    Run only tests with specific tags (optional)

.PARAMETER ExcludeTag
    Exclude tests with specific tags (optional)

.PARAMETER CodeCoverage
    Enable code coverage analysis (default: true)

.PARAMETER OutputFormat
    Output format for test results: Console, NUnitXml, JUnitXml (default: Console)

.PARAMETER CI
    Run in CI mode with appropriate output formatting (default: false)

.EXAMPLE
    .\Run-Tests.ps1
    Runs all tests with default settings

.EXAMPLE
    .\Run-Tests.ps1 -TestName "Convert-PackageName.Tests.ps1"
    Runs only the Convert-PackageName tests

.EXAMPLE
    .\Run-Tests.ps1 -Tag "Unit" -CodeCoverage $true
    Runs only unit tests with code coverage

.EXAMPLE
    .\Run-Tests.ps1 -CI $true -OutputFormat "JUnitXml"
    Runs in CI mode with JUnit XML output
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TestName = "*",

    [Parameter(Mandatory = $false)]
    [string[]]$Tag = @(),

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeTag = @(),

    [Parameter(Mandatory = $false)]
    [bool]$CodeCoverage = $true,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Console", "NUnitXml", "JUnitXml")]
    [string]$OutputFormat = "Console",

    [Parameter(Mandatory = $false)]
    [bool]$CI = $false
)

# Ensure we're in the correct directory
Set-Location $PSScriptRoot

Write-Host "=== avm-tf-to-ipm-module Test Runner ===" -ForegroundColor Green
Write-Host "Test Location: $PSScriptRoot" -ForegroundColor Cyan
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan

# Check if Pester is installed
try {
    $PesterVersion = Get-Module -Name Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $PesterVersion) {
        throw "Pester module not found"
    }
    Write-Host "Pester Version: $($PesterVersion.Version)" -ForegroundColor Cyan

    # Import Pester (force v5+ for best compatibility)
    if ($PesterVersion.Version.Major -lt 5) {
        Write-Warning "Pester version 5.0 or higher is recommended. Current version: $($PesterVersion.Version)"
    }
    Import-Module Pester -Force
}
catch {
    Write-Error "Failed to import Pester module. Please install Pester v5.0+: Install-Module -Name Pester -Force"
    exit 1
}

# Ensure the module is available for testing
$ModulePath = Join-Path $PSScriptRoot "../avm-tf-to-ipm-module"
if (-not (Test-Path $ModulePath)) {
    Write-Error "Module directory not found at: $ModulePath"
    exit 1
}

# Build test path pattern
$TestPaths = @()
if ($TestName -eq "*") {
    $TestPaths = Get-ChildItem -Path $PSScriptRoot -Filter "*.Tests.ps1" | Select-Object -ExpandProperty FullName
} else {
    $TestPaths = Get-ChildItem -Path $PSScriptRoot -Filter "*$TestName*" | Where-Object { $_.Name -like "*.Tests.ps1" } | Select-Object -ExpandProperty FullName
}

if ($TestPaths.Count -eq 0) {
    Write-Warning "No test files found matching pattern: $TestName"
    exit 0
}

Write-Host "Found $($TestPaths.Count) test file(s):" -ForegroundColor Yellow
$TestPaths | ForEach-Object { Write-Host "  - $(Split-Path $_ -Leaf)" -ForegroundColor Yellow }

# Configure Pester
$PesterConfiguration = [PesterConfiguration]::Default

# Run configuration
$PesterConfiguration.Run.Path = $TestPaths
$PesterConfiguration.Run.PassThru = $true
$PesterConfiguration.Run.Exit = $CI

# Filter configuration
if ($Tag.Count -gt 0) {
    $PesterConfiguration.Filter.Tag = $Tag
}
if ($ExcludeTag.Count -gt 0) {
    $PesterConfiguration.Filter.ExcludeTag = $ExcludeTag
}

# Output configuration
if ($CI) {
    $PesterConfiguration.Output.Verbosity = 'Normal'
    $PesterConfiguration.Output.CIFormat = 'Auto'
} else {
    $PesterConfiguration.Output.Verbosity = 'Detailed'
}

# Test result configuration
if ($OutputFormat -ne "Console") {
    $PesterConfiguration.TestResult.Enabled = $true
    $PesterConfiguration.TestResult.OutputFormat = $OutputFormat
    $PesterConfiguration.TestResult.OutputPath = "TestResults.$($OutputFormat.ToLower() -replace 'xml$', '').xml"
    Write-Host "Test results will be saved to: $($PesterConfiguration.TestResult.OutputPath)" -ForegroundColor Cyan
}

# Code coverage configuration
if ($CodeCoverage) {
    $PesterConfiguration.CodeCoverage.Enabled = $true
    $PesterConfiguration.CodeCoverage.Path = @(
        Join-Path $ModulePath "public\Convert-PackageName.ps1"
        Join-Path $ModulePath "public\New-IpmPackageName.ps1"
        Join-Path $ModulePath "public\Write-Log.ps1"
    )
    $PesterConfiguration.CodeCoverage.OutputFormat = 'JaCoCo'
    $PesterConfiguration.CodeCoverage.OutputPath = 'CodeCoverage.xml'
    Write-Host "Code coverage will be saved to: CodeCoverage.xml" -ForegroundColor Cyan
}

# Run the tests
Write-Host "`n=== Running Tests ===" -ForegroundColor Green
$StartTime = Get-Date

try {
    $TestResults = Invoke-Pester -Configuration $PesterConfiguration

    $EndTime = Get-Date
    $Duration = $EndTime - $StartTime

    Write-Host "`n=== Test Results Summary ===" -ForegroundColor Green
    Write-Host "Duration: $($Duration.TotalSeconds.ToString('F2')) seconds" -ForegroundColor Cyan
    Write-Host "Total Tests: $($TestResults.TotalCount)" -ForegroundColor Cyan
    Write-Host "Passed: $($TestResults.PassedCount)" -ForegroundColor Green
    Write-Host "Failed: $($TestResults.FailedCount)" -ForegroundColor $(if ($TestResults.FailedCount -eq 0) { 'Green' } else { 'Red' })
    Write-Host "Skipped: $($TestResults.SkippedCount)" -ForegroundColor Yellow

    if ($CodeCoverage -and $TestResults.CodeCoverage) {
        $CoveragePercent = [math]::Round(($TestResults.CodeCoverage.CoveragePercent), 2)
        Write-Host "Code Coverage: $CoveragePercent%" -ForegroundColor $(if ($CoveragePercent -ge 80) { 'Green' } elseif ($CoveragePercent -ge 60) { 'Yellow' } else { 'Red' })
    }

    # Exit with appropriate code
    if ($TestResults.FailedCount -gt 0) {
        Write-Host "`nSome tests failed. Check the output above for details." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "`nAll tests passed successfully!" -ForegroundColor Green
        exit 0
    }
}
catch {
    Write-Error "An error occurred while running tests: $_"
    exit 1
}