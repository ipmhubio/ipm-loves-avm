function Copy-ExtractedToIpmBuild
{
    param (
        [string]$ExtractedPath,
        [string]$VersionFolderPath
    )

    # Create build-for-ipm folder at the same level as extracted and release.tar.gz
    $buildForIpmPath = Join-Path (Split-Path $VersionFolderPath -Parent) "build-for-ipm"
    if (Test-Path $buildForIpmPath)
    {
        Remove-Item -Path $buildForIpmPath -Recurse -Force
    }
    New-Item -Path $buildForIpmPath -ItemType Directory -Force | Out-Null

    # Get all items from extracted folder, excluding dot folders
    Get-ChildItem -Path $ExtractedPath -Recurse | Where-Object {
        # Exclude dot folders and their contents
        $_.FullName -notmatch '\\\..*\\' -and
        # Exclude .terraform folder
        $_.FullName -notmatch '\\\.terraform\\' -and
        # Exclude tests folder
        $_.FullName -notmatch '\\tests\\' -and
        # Exclude avm.bat
        $_.Name -ne 'avm.bat' -and
        # Exclude .log files
        $_.Extension -ne '.log' -and
        # exclude Makefile, avm CODE_OF_CONDUCT.md
        $_.Name -notmatch 'Makefile|CODE_OF_CONDUCT.md' -and
        # Exclude dot folders at root level
        $_.Name -notmatch '^\.'
    } | ForEach-Object {
        $relativePath = $_.FullName.Substring($ExtractedPath.Length + 1)
        $targetPath = Join-Path $buildForIpmPath $relativePath

        if ($_.PSIsContainer)
        {
            New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
        }
        else
        {
            $targetDir = Split-Path $targetPath -Parent
            if (-not (Test-Path $targetDir))
            {
                New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path $_.FullName -Destination $targetPath -Force
        }
    }

    return $buildForIpmPath
}

Export-ModuleMember -Function Copy-ExtractedToIpmBuild
