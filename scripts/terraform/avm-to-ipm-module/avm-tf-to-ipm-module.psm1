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
      }
      Catch
      {
        Write-Error "Failed to import '$($File.FullName)'"
      }
    }
  }
}

# Load all public functions
$publicFuncFolder = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
$publicFunctions = Get-ChildItem -Path $publicFuncFolder -Filter '*.ps1'
foreach ($function in $publicFunctions)
{
  . $function.FullName
}

Export-ModuleMember -Function @(
  'Convert-PackageName',
  'Get-AvmTerraformModule',
  'Get-AzureAvmReleases',
  'Get-NewReleases',
  'Get-PackageVersionState',
  'Get-PublishedPackages',
  'Get-ReleaseArchive',
  'Initialize-AzureStorageTable',
  'Initialize-Environment',
  'Invoke-AvmRelease',
  'Invoke-IpmHubPackageEnsurance',
  'Publish-ToIpm',
  'Send-TeamsNotification',
  'Test-TerraformModule',
  'Update-ModuleDocumentation',
  'Update-PackageVersionState',
  'Update-ReleaseNotes',
  'Update-TelemetryDefault',
  'Update-TelemetryDefaultInMarkdown',
  'Write-Log'

)

