function Initialize-Environment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$StagingDirectory
    )
    Write-Log "Initializing environment..."

    # Create staging directory if it doesn't exist
    if (-not (Test-Path -Path $StagingDirectory)) {
        New-Item -Path $StagingDirectory -ItemType Directory | Out-Null
        Write-Log "Created staging directory: $StagingDirectory" -Level "INFO"
    }

    # Install required PowerShell modules if not present
    $requiredModules = @('Az.Storage')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Log "Installing required module: $module" -Level "INFO"
            Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
        }
    }

    # Validate IPM client exists
    try {
        $ipmVersion = & ipm --version
        Write-Log "IPM client version: $ipmVersion" -Level "INFO"
    }
    catch {
        Write-Log "Failed to run IPM client. Please ensure it is installed and accessible." -Level "ERROR"
        throw "IPM client validation failed"
    }

    Write-Log "Environment initialization complete" -Level "SUCCESS"
}