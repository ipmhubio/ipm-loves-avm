function Publish-ToIpm
{
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        [Parameter(Mandatory = $true)]
        [string]$ipmOrganization,
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [bool]$LocalRun = $false
    )

    try
    {
        $version = $version -replace '-', '.'
        if (-not (Get-Command -Name New-IpmPackageName -ErrorAction SilentlyContinue)) {
            throw "The function 'New-IpmPackageName' is not defined or available in the current scope."
        }
        $PackageName = New-IpmPackageName -TerraformName $PackageName
        Write-Log "Publishing $PackageName v$Version to IPM..." -Level "INFO"

        $fullPackageName = "{0}/{1}" -f $ipmOrganization, $PackageName
        $publishCommand = "ipm publish --package $fullPackageName --version $version --folder $PackagePath --non-interactive"

        if ($LocalRun)
        {
            Write-Log "Local run - Command to execute: $publishCommand" -Level "INFO"
            return [PSCustomObject]@{
                Success = $true
                Message = "Local run completed successfully for package: $fullPackageName"
            }
        }
        else
        {
            $process = Start-Process -FilePath ipm -ArgumentList @(
                "publish",
                "--package", $fullPackageName,
                "--version", $version,
                "--folder", $PackagePath,
                "--non-interactive"
            ) -PassThru -Wait

            if ($process.ExitCode -ne 0)
            {
                $errorMessage = "Failed to publish $fullPackageName v$Version to IPM (Exit code: $($process.ExitCode))"
                Write-Log $errorMessage -Level "ERROR"
                return [PSCustomObject]@{
                    Success = $false
                    Message = $errorMessage
                }
            }

            Write-Log "Successfully published $fullPackageName v$Version to IPM" -Level "SUCCESS"
            return [PSCustomObject]@{
                Success = $true
                Message = $successMessage
            }
        }
    }
    catch
    {
        $errorMessage = "Error publishing to IPM: $($_.Exception.Message)"
        Write-Log $errorMessage -Level "ERROR"
        return [PSCustomObject]@{
            Success = $false
            Message = $errorMessage
        }
    }
}