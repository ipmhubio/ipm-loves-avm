function Update-ModuleDocumentation
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModulePath,

        [Parameter(Mandatory = $true, ParameterSetName = "SecureSasToken")]
        [ValidateNotNull()]
        [SecureString] $SecureSasToken,

        [Parameter(Mandatory = $true, ParameterSetName = "SasTokenFromEnvVariable")]
        [String] $SasTokenFromEnvironmentVariable,

        [Parameter(Mandatory = $true, ParameterSetName = "UnsecureSasToken")]
        [ValidateNotNullOrEmpty()]
        [String] $SasToken,

        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $false)]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [String] $StateAccount = "ipmhubsponstor01weust",

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [String] $StateTableName = "AvmPackageReleaseNotes",

        [Parameter(Mandatory = $false)]
        [Switch] $RunLocal = $false
    )

    try
    {
        Write-Log "Updating module documentation in $ModulePath" -Level "INFO"

        # Pass the appropriate SAS token parameter to Get-CombinedReleaseNotes
        $sasParams = @{}
        switch ($PSCmdlet.ParameterSetName) {
            "SecureSasToken" { $sasParams.Add("SecureSasToken", $SecureSasToken) }
            "SasTokenFromEnvVariable" { $sasParams.Add("SasTokenFromEnvironmentVariable", $SasTokenFromEnvironmentVariable) }
            "UnsecureSasToken" { $sasParams.Add("SasToken", $SasToken) }
        }

        # Get combined release notes using REST API approach
        $releaseNotes = Get-CombinedReleaseNotes @sasParams `
            -PackageName $PackageName `
            -Version $Version `
            -ModulePath $ModulePath `
            -StateAccount $StateAccount `
            -StateTableName $StateTableName `
            -RunLocal:$RunLocal

        # Create or update RELEASENOTES.md is now handled inside Get-CombinedReleaseNotes
        # so we don't need to do it here anymore
        $releaseNotesPath = Join-Path $ModulePath "RELEASENOTES.md"
        Write-Log "Successfully updated release notes at $releaseNotesPath" -Level "INFO"

        return $true
    }
    catch
    {
        $errorDetails = @{
            Message    = $_.Exception.Message
            Line       = $_.InvocationInfo.ScriptLineNumber
            ScriptName = $_.InvocationInfo.ScriptName
            StackTrace = $_.Exception.StackTrace
        } | ConvertTo-Json
        Write-Log "Failed to update module documentation: $errorDetails" -Level "ERROR"
        return $false
    }
}