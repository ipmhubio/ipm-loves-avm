# Pester Configuration for avm-tf-to-ipm-module tests
# This file defines the test configuration following Pester v5 best practices

@{
    Run = @{
        # Path to the tests - all .Tests.ps1 files in the tests directory
        Path = @(
            '.\Convert-PackageName.Tests.ps1'
            '.\New-IpmPackageName-Simple.Tests.ps1'
        )
        # Exclude any files that should not be run
        ExcludePath = @()
        # Tags to include/exclude
        TagFilter = @()
        ExcludeTagFilter = @()
        # Exit code configuration
        Exit = $true
        Throw = $false
        # Passthru to get detailed results
        PassThru = $true
    }

    Output = @{
        # Verbosity level
        Verbosity = 'Detailed'
        # Output format
        StackTraceVerbosity = 'Filtered'
        CIFormat = 'Auto'
    }

    TestResult = @{
        # Enable test result output
        Enabled = $true
        # Output path for test results
        OutputPath = './TestResults.xml'
        # Output format (NUnitXml, JUnitXml)
        OutputFormat = 'NUnitXml'
        # Test result details
        TestSuiteName = 'avm-tf-to-ipm-module'
    }

    CodeCoverage = @{
        # Enable code coverage
        Enabled = $true
        # Path to source files for coverage analysis
        Path = @(
            '../avm-tf-to-ipm-module/public/Convert-PackageName.ps1'
            '../avm-tf-to-ipm-module/public/New-IpmPackageName.ps1'
        )
        # Output path for coverage report
        OutputPath = './CodeCoverage.xml'
        # Output format
        OutputFormat = 'JaCoCo'
        # Use breakpoints for coverage (more accurate but slower)
        UseBreakpoints = $false
    }

    Should = @{
        # Error action for Should assertions
        ErrorAction = 'Stop'
    }

    Debug = @{
        # Show debug information
        ShowFullErrors = $false
        WriteDebugMessages = $false
        WriteDebugMessagesFrom = @()
        ShowNavigationMarkers = $false
        ReturnRawResultObject = $false
    }
}