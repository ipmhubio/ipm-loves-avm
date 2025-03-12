function Publish-ToIpm
{
    param (
        [string]$PackagePath,
        [string]$PackageName,
        [string]$Version,
        [bool]$LocalRun = $false
    )

    try
    {
        Write-Log "Publishing $PackageName v$Version to IPM..." -Level "INFO"

        # Construct the publish command
        $publishCommand = "ipm publish --package $PackageName --version $Version --folder $PackagePath --non-interactive"

        if ($LocalRun)
        {
            # When running locally, just output the command
            Write-Log "Local run - Command to execute:" -Level "INFO"
            Write-Log $publishCommand -Level "INFO"
            return $true
        }
        else
        {
            # This is a placeholder for your actual IPM publish command
            $process = Start-Process -FilePath $IpmClientPath -ArgumentList @(
                "publish",
                "--package", $PackageName,
                "--version", $Version,
                "--folder", $PackagePath,
                "--non-interactive"
            ) -PassThru -Wait

            if ($process.ExitCode -ne 0)
            {
                Write-Log "Failed to publish $PackageName v$Version to IPM" -Level "ERROR"
                return $false
            }

            Write-Log "Successfully published $PackageName v$Version to IPM" -Level "SUCCESS"
            return $true
        }
    }
    catch
    {
        Write-Log "Error publishing to IPM: $_" -Level "ERROR"
        return $false
    }
}