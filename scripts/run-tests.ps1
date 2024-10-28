[CmdletBinding()]
Param(
  [Parameter(Mandatory = $True)]
  [String] $TestRootPath
)

$ModuleTestsFile = Join-Path -Path (Split-Path $PSScriptRoot -Parent) -ChildPath "tests" -AdditionalChildPath "avm-modules.tests.ps1"
$Container = New-Pestercontainer -Path $ModuleTestsFile -Data @{ PackagesRootPath = $TestRootPath }
Invoke-Pester -Container $Container -Output Detailed