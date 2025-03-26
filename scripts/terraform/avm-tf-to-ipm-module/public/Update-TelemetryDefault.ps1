function Update-TelemetryDefault
{
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $filesUpdated = $false
  # Get all .tf files recursively
  $files = Get-ChildItem -Path $Path -Filter "*.tf" -Recurse

  foreach ($file in $files)
  {
    $content = Get-Content -Path $file.FullName -Raw

    # Match the entire variable block regardless of key order
    $pattern = '(?ms)(variable\s+"enable_telemetry"\s*{[^{]*?)(default\s*=\s*true)([^}]*})'

    if ($content -match 'variable\s+"enable_telemetry"')
    {
      Write-Verbose "Processing file: $($file.FullName)"

      # Replace using a more specific pattern that captures the whole block
      $newContent = $content -replace $pattern, '$1default = false$3'

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