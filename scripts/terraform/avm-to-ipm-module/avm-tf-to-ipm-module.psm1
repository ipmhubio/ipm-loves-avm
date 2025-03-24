<#

  2024.01.22 Bas Berkhout - Rip0ff

#>
[CmdletBinding()]
Param(
  [Bool] $VerboseLogging = $False
)

If ($VerboseLogging)
{
  $VerbosePreference = "Continue"
}

$ErrorActionPreference = "Stop"
$WarningPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# Set variables used in the module
Write-Verbose $PSScriptRoot
Write-Verbose 'Import PowerShell subscripts'

# Create an array to track functions to export
$functionsToExport = @()

# Dot source the files.
ForEach ($Folder in @('Private', 'Public'))
{
  $Root = Join-Path -Path $PSScriptRoot -ChildPath $Folder

  If (Test-Path -Path $Root -PathType "Container")
  {
    Write-Verbose "Processing '$($Folder)' Folder..."

    $Files = Get-ChildItem -Path $Root -Filter "*.ps1" -Recurse | Where-Object { $_.name -notlike '*.Tests.ps1' }
    ForEach ($File in $Files)
    {
      Try
      {
        Write-Verbose "Importing '$($File.FullName)'"
        . $File.FullName

        # If it's a public function, add to export list
        if ($Folder -eq 'Public') {
          # Extract function name from the file (assuming file name matches function name)
          $functionName = $File.BaseName
          $functionsToExport += $functionName
        }
      }
      Catch
      {
        Write-Error "Failed to import '$($File.FullName)'"
      }
    }
  }
}

# Remove the redundant function loading section
# No need to load public functions twice

# Export the functions that were loaded from the Public folder
Export-ModuleMember -Function @(
  'Convert-PackageName',
  'Get-AvmTerraformModule',
  'Get-AzureAvmReleases',
  'Get-NewReleases',
  'Get-PackageVersionState',
  'Get-PublishedPackages',
  'Get-TableEntities',
  'Get-ReleaseArchive',
  'Initialize-AzureStorageTable',
  'Initialize-Environment',
  'Invoke-AvmRelease',
  'Invoke-IpmHubPackageEnsurance',
  'New-IpmPackageName',
  'Publish-ToIpm',
  'Send-TeamsNotification',
  'Test-TerraformModule',
  'Update-ModuleDocumentation',
  'Update-PackageVersionState',
  'Update-ReleaseNotes',
  'Update-TelemetryDefault',
  'Update-TelemetryDefaultInMarkdown',
  'Write-Log',
  'Get-ValidPackageName',
  'Add-DisclaimerFile'
)