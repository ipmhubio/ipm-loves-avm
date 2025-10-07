BeforeAll {
    # Import the module under test
    $ModuleRoot = Join-Path $PSScriptRoot "../avm-tf-to-ipm-module"
    Import-Module -Name $ModuleRoot -Force

    # Create a test log directory in TestDrive
    $TestLogDir = Join-Path $TestDrive "logs"
    $TestLogPath = Join-Path $TestLogDir "test-log.log"
}

Describe "Write-Log" -Tag "Unit" {
    Context "Basic logging functionality" {
        BeforeEach {
            # Clean up any existing test log files
            if (Test-Path $TestLogDir)
            {
                Remove-Item $TestLogDir -Recurse -Force
            }
        }

        It "Should write log message to console and file" {
            $Message = "Test log message"

            # Capture console output
            $ConsoleOutput = Write-Log -Message $Message -LogPath $TestLogPath -Level "INFO" 6>&1

            # Verify file was created and contains the message
            Test-Path $TestLogPath | Should -Be $true
            $LogContent = Get-Content $TestLogPath
            $LogContent | Should -Not -BeNullOrEmpty
            $LogContent[0] | Should -Match $Message
        }

        It "Should create log directory if it doesn't exist" {
            $NonExistentLogDir = Join-Path $TestDrive "non-existent-logs"
            $NonExistentLogPath = Join-Path $NonExistentLogDir "test.log"

            Write-Log -Message "Test" -LogPath $NonExistentLogPath

            Test-Path $NonExistentLogDir | Should -Be $true
            Test-Path $NonExistentLogPath | Should -Be $true
        }

        It "Should use default log path when not specified" {
            # This test checks the default behavior
            $DefaultLogPath = "./logs/ipm-process.log"

            # Mock Test-Path and New-Item to avoid actual file system operations
            Mock Test-Path { $false } -ParameterFilter { $Path -like "*logs*" }
            Mock New-Item { } -ParameterFilter { $ItemType -eq "Directory" }
            Mock Add-Content { } -ParameterFilter { $Path -eq $DefaultLogPath }

            Write-Log -Message "Test with default path"

            Should -Invoke Add-Content -ParameterFilter { $Path -eq $DefaultLogPath }
        }
    }

    Context "Log level handling" {
        BeforeEach {
            if (Test-Path $TestLogDir)
            {
                Remove-Item $TestLogDir -Recurse -Force
            }
        }

        It "Should handle different log levels correctly" -TestCases @(
            @{ Level = "INFO"; ExpectedLevel = "INFO" }
            @{ Level = "WARNING"; ExpectedLevel = "WARNING" }
            @{ Level = "ERROR"; ExpectedLevel = "ERROR" }
            @{ Level = "SUCCESS"; ExpectedLevel = "SUCCESS" }
            @{ Level = "DEBUG"; ExpectedLevel = "DEBUG" }
        ) {
            param($Level, $ExpectedLevel)

            Write-Log -Message "Test message" -Level $Level -LogPath $TestLogPath

            $LogContent = Get-Content $TestLogPath
            $LogContent[0] | Should -Match "\[$ExpectedLevel\]"
        }

        It "Should use INFO as default level when not specified" {
            Write-Log -Message "Test message" -LogPath $TestLogPath

            $LogContent = Get-Content $TestLogPath
            $LogContent[0] | Should -Match "\[INFO\]"
        }

        It "Should validate log level parameter" {
            { Write-Log -Message "Test" -Level "INVALID" -LogPath $TestLogPath } | Should -Throw
        }
    }

    Context "Log message formatting" {
        BeforeEach {
            if (Test-Path $TestLogDir)
            {
                Remove-Item $TestLogDir -Recurse -Force
            }
        }

        It "Should include timestamp in log message" {
            Write-Log -Message "Test message" -LogPath $TestLogPath

            $LogContent = Get-Content $TestLogPath
            # Should match pattern like [2024-10-07 15:30:45]
            $LogContent[0] | Should -Match "\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]"
        }

        It "Should include caller information in log message" {
            Write-Log -Message "Test message" -LogPath $TestLogPath

            $LogContent = Get-Content $TestLogPath
            # Should include file name and line number
            $LogContent[0] | Should -Match "\[.*\.ps1 : \d+\]"
        }

        It "Should format message with fixed-width columns" {
            Write-Log -Message "Test message" -LogPath $TestLogPath

            $LogContent = Get-Content $TestLogPath
            # Verify the format: [timestamp] [level] [location] message
            $LogContent[0] | Should -Match "^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]\s+\[INFO\]\s+\[.*\]\s+Test message$"
        }

        It "Should handle special characters in messages" {
            $SpecialMessage = "Test with special chars: !@#$%^&*()_+-=[]{}|;':"
            Write-Log -Message $SpecialMessage -LogPath $TestLogPath

            $LogContent = Get-Content $TestLogPath
            $LogContent[0] | Should -Match [regex]::Escape($SpecialMessage)
        }

        It "Should handle multiline messages correctly" {
            $MultilineMessage = "Line 1`nLine 2`nLine 3"
            Write-Log -Message $MultilineMessage -LogPath $TestLogPath

            $LogContent = Get-Content $TestLogPath -Raw
            $LogContent | Should -Match "Line 1.*Line 2.*Line 3"
        }
    }

    Context "Error handling" {
        BeforeEach {
            if (Test-Path $TestLogDir)
            {
                Remove-Item $TestLogDir -Recurse -Force
            }
        }

        It "Should handle file write errors gracefully" {
            # Create a read-only directory to force a write error
            $ReadOnlyDir = Join-Path $TestDrive "readonly"
            New-Item -ItemType Directory -Path $ReadOnlyDir -Force
            $ReadOnlyLogPath = Join-Path $ReadOnlyDir "test.log"

            # Mock Add-Content to throw an error
            Mock Add-Content { throw "Access denied" }

            # Should not throw, but should output error to console
            { Write-Log -Message "Test" -LogPath $ReadOnlyLogPath } | Should -Not -Throw

            Should -Invoke Add-Content
        }

        It "Should continue with console output even if file write fails" {
            Mock Add-Content { throw "File write error" }

            # Capture any host output
            $Output = Write-Log -Message "Test message" -LogPath $TestLogPath 6>&1

            # Should still attempt to write to console (no exception thrown)
            { Write-Log -Message "Test message" -LogPath $TestLogPath } | Should -Not -Throw
        }
    }

    Context "Console output behavior" {
        It "Should output with different colors for different levels" {
            # Note: Testing console colors is complex, but we can verify the function doesn't throw
            @("INFO", "WARNING", "ERROR", "SUCCESS", "DEBUG") | ForEach-Object {
                { Write-Log -Message "Test $_" -Level $_ -LogPath $TestLogPath } | Should -Not -Throw
            }
        }
    }

    Context "Parameter validation" {
        It "Should require Message parameter" {
            { Write-Log -LogPath $TestLogPath } | Should -Throw
        }

        It "Should accept empty message" {
            { Write-Log -Message "" -LogPath $TestLogPath } | Should -Not -Throw
        }

        It "Should handle null message parameter" {
            { Write-Log -Message $null -LogPath $TestLogPath } | Should -Not -Throw
        }
    }

    Context "Call stack information" {
        It "Should correctly identify caller information" {
            function Test-CallerFunction
            {
                Write-Log -Message "Called from function" -LogPath $TestLogPath
            }

            Test-CallerFunction

            $LogContent = Get-Content $TestLogPath
            # Should show the test script as the caller, not Write-Log itself
            $LogContent[0] | Should -Match "Write-Log\.Tests\.ps1"
        }

        It "Should handle unknown caller gracefully" {
            # Mock Get-PSCallStack to return limited info
            Mock Get-PSCallStack {
                return @(
                    [PSCustomObject]@{ ScriptName = $null; ScriptLineNumber = 0 }
                    [PSCustomObject]@{ ScriptName = $null; ScriptLineNumber = 0 }
                )
            }

            Write-Log -Message "Test unknown caller" -LogPath $TestLogPath

            $LogContent = Get-Content $TestLogPath
            $LogContent[0] | Should -Match "\[Unknown : 0\]"
        }
    }

    Context "Performance and edge cases" {
        BeforeEach {
            if (Test-Path $TestLogDir)
            {
                Remove-Item $TestLogDir -Recurse -Force
            }
        }

        It "Should handle very long messages" {
            $LongMessage = "A" * 10000
            { Write-Log -Message $LongMessage -LogPath $TestLogPath } | Should -Not -Throw

            $LogContent = Get-Content $TestLogPath -Raw
            $LogContent | Should -Match ([regex]::Escape($LongMessage))
        }

        It "Should handle concurrent logging attempts" {
            # This is a basic test - real concurrent testing would require more complex setup
            1..5 | ForEach-Object {
                Write-Log -Message "Concurrent message $_" -LogPath $TestLogPath
            }

            $LogContent = Get-Content $TestLogPath
            $LogContent.Count | Should -Be 5
        }

        It "Should handle relative and absolute paths correctly" {
            $RelativePath = ".\logs\relative-test.log"
            { Write-Log -Message "Relative path test" -LogPath $RelativePath } | Should -Not -Throw
        }
    }
}