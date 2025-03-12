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

        #Trim terraform-azurerm-avm-res- prefix from package name
        $PackageName = $PackageName -replace "terraform-azurerm-avm-res-", ""
        $PackageName = $PackageName -replace "terraform-avm-azurerm-res-", ""

        Write-Log "Publishing $PackageName v$Version to IPM..." -Level "INFO"

        if ([string]::IsNullOrEmpty($PackageName))
        {
            return [PSCustomObject]@{
                Success = $false
                Message = "Package name cannot be empty"
            }
        }

        if ($PackageName.Length -gt 36)
        {
            Write-Log "Package name $PackageName is more than 36 characters. Trimming to 36 characters." -Level "INFO"
            $convertedPackageName = Convert-PackageName -PackageName $PackageName
            if ($convertedPackageName -eq $false)
            {
                return [PSCustomObject]@{
                    Success = $false
                    Message = "Failed to convert package name: $PackageName"
                }
            }
            $PackageName = $convertedPackageName
        }

        $fullPackageName = "{0}/{1}" -f $ipmOrganization, $PackageName
        $publishCommand = "ipm publish --package $fullPackageName --version $Version --folder $PackagePath --non-interactive"

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
            $process = Start-Process -FilePath $IpmClientPath -ArgumentList @(
                "publish",
                "--package", $fullPackageName,
                "--version", $Version,
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

            $successMessage = "Successfully published $fullPackageName v$Version to IPM"
            Write-Log $successMessage -Level "SUCCESS"
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