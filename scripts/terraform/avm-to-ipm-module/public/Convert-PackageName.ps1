function Convert-PackageName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$packageName,

        [Parameter(Mandatory = $false)]
        [string]$SettingsPath = (Join-Path $PSScriptRoot "../../settings.jsonc")
    )

    try {
        # Read and parse the settings file
        $settingsContent = Get-Content -Path $SettingsPath -Raw
        $settings = $settingsContent | ConvertFrom-Json

        # Start with the input string
        $result = $packageName
        $replacementMade = $false

        # Apply each replacement in order
        foreach ($replacement in $settings.nameReplacementments) {
            if ($result -eq $replacement.search) {
                $result = $replacement.replacement
                $replacementMade = $true
                break # Exit after first exact match
            }
        }

        # Return false if no exact match was found
        if (-not $replacementMade) {
            return $false
        }
        return $result
    }
    catch {
        Write-Warning "Error processing name mapping: $_"
        return $false
    }
}