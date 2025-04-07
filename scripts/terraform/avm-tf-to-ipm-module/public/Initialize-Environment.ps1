function Initialize-Environment
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$StagingDirectory
    )
    Write-Log "Initializing environment..."

    # Create staging directory if it doesn't exist
    if (-not (Test-Path -Path $StagingDirectory))
    {
        New-Item -Path $StagingDirectory -ItemType Directory | Out-Null
        Write-Log "Created staging directory: $StagingDirectory" -Level "INFO"
    }


    # Validate IPM client exists
    try
    {
        $ipmVersion = & ipm --version
        Write-Log "IPM client version: $ipmVersion" -Level "INFO"
    }
    catch
    {
        Write-Log "Failed to run IPM client. Please ensure it is installed and accessible." -Level "ERROR"
        throw "IPM client validation failed"
    }

    Write-Log "Environment initialization complete" -Level "SUCCESS"
}