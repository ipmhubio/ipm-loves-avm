function Update-ModuleDocumentation
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModulePath,

        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Cosmos.Table.CloudTable]$Table,

        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $false)]
        [string]$Version
    )

    try
    {
        Write-Log "Updating module documentation in $ModulePath" -Level "INFO"


        # Get combined release notes using existing table
        $releaseNotes = Get-CombinedReleaseNotes -Table $Table -PackageName $packageName -version $Version -modulePath $ModulePath

        # Create or update RELEASENOTES.md
        $releaseNotesPath = Join-Path $ModulePath "RELEASENOTES.md"
        Set-Content -Path $releaseNotesPath -Value $releaseNotes -Force

        Write-Log "Successfully updated release notes at $releaseNotesPath" -Level "INFO"
        return $true
    }
    catch
    {
        Write-Log "Failed to update module documentation: $packageName" -Level "ERROR"
        return $false
    }
}