function Update-TelemetryDefaultInMarkdown
{
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $filesUpdated = $false
  # Get all markdown files recursively
  $files = Get-ChildItem -Path $Path -Filter "*.md" -Recurse

  foreach ($file in $files)
  {
    $content = Get-Content -Path $file.FullName -Raw

    # Pattern to match the enable_telemetry section
    $pattern = '(?ms)(### <a name="input_enable_telemetry".*?Default:\s*)`true`(\s*###)'

    if ($content -match '### <a name="input_enable_telemetry"')
    {
      Write-Verbose "Processing file: $($file.FullName)"

      # Replace default value
      $newContent = $content -replace $pattern, '$1`false`$2'

      if ($content -ne $newContent)
      {
        Write-Host "Updating file: $($file.FullName)"
        $newContent | Set-Content -Path $file.FullName -NoNewline
        $filesUpdated = $true
      }
    }
  }

  return $filesUpdated
}

function Update-AVMModuleSourceInMarkdown
{
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$ipmPackageName
  )

  $filesUpdated = $false
  # Get all markdown files recursively
  $files = Get-ChildItem -Path $Path -Filter "*.md" -Recurse

  foreach ($file in $files)
  {
    $content = Get-Content -Path $file.FullName -Raw

    # Pattern to match the source line with Azure/avm module reference
    $pattern = '(source\s*=\s*)"Azure/([^/"]+)/azurerm"'

    if ($content -match 'source\s*=\s*"Azure/')
    {
      Write-Verbose "Processing file: $($file.FullName)"

      # Replace source path
      $newContent = $content -replace $pattern, "`$1`"packages/$ipmPackageName`""

      if ($content -ne $newContent)
      {
        Write-Host "Updating file: $($file.FullName)"
        $newContent | Set-Content -Path $file.FullName -NoNewline
        $filesUpdated = $true
      }
    }
  }

  return $filesUpdated
}