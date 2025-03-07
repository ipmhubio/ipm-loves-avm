
param (
    [Parameter(Mandatory = $true)]
    [string]$NewJsonPath,

    [Parameter(Mandatory = $true)]
    [string]$ExistingJsonPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputJsonPath,

     [Parameter(Mandatory = $true)]
     [string]$GithubToken
)

# Function to read and parse JSON files
function Read-JsonFile {
    param (
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Error "File not found: $Path"
        exit 1
    }

    try {
        $content = Get-Content -Path $Path -Raw
        $json = $content | ConvertFrom-Json
        return $json
    }
    catch {
        Write-Error "Failed to parse JSON file: $_"
        exit 1
    }
}

# Read both JSON files
Write-Host "Reading JSON files..." -ForegroundColor Cyan
$newJson = Read-JsonFile -Path $NewJsonPath
$existingJson = Read-JsonFile -Path $ExistingJsonPath

# Create a hashtable for quick lookup of existing packages
$existingPackages = @{}
foreach ($package in $existingJson) {
    $existingPackages[$package.name] = $package
}

# Initialize result arrays
$newPackages = @()
$packagesWithNewReleases = @()

# Check for new packages and new releases
Write-Host "Analyzing differences..." -ForegroundColor Cyan
foreach ($newPackage in $newJson) {
    if (-not $existingPackages.ContainsKey($newPackage.name)) {
        # This is a completely new package
        Write-Host "New package found: $($newPackage.name)" -ForegroundColor Green
        $newPackages += $newPackage
        continue
    }

    # Check for new releases in existing packages
    $existingPackage = $existingPackages[$newPackage.name]
    $existingReleases = @{}
    foreach ($release in $existingPackage.releases) {
        if ($release.PSObject.Properties.Name -contains "version") {
            $existingReleases[$release.version] = $true
        }
    }

    $newReleasesForPackage = @()
    foreach ($release in $newPackage.releases) {
        if ($release.PSObject.Properties.Name -contains "version" -and -not $existingReleases.ContainsKey($release.version)) {
            # This is a new release
            $newReleasesForPackage += $release
        }
    }

    if ($newReleasesForPackage.Count -gt 0) {
        Write-Host "Package '$($newPackage.name)' has $($newReleasesForPackage.Count) new release(s)" -ForegroundColor Yellow
        foreach ($release in $newReleasesForPackage) {
            Write-Host "  - v$($release.version) released on $(Get-Date $release.published_at -Format 'yyyy-MM-dd')" -ForegroundColor Yellow
        }

        # Create a copy of the package with only the new releases
        $packageWithNewReleases = [PSCustomObject]@{
            name = $newPackage.name
            url = $newPackage.url
            releases = $newReleasesForPackage
            release_count = $newReleasesForPackage.Count
        }

        $packagesWithNewReleases += $packageWithNewReleases
    }
}

# Combine new packages and packages with new releases
$result = $newPackages + $packagesWithNewReleases

# Output summary
Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "Found $($newPackages.Count) new package(s)" -ForegroundColor Green
Write-Host "Found $($packagesWithNewReleases.Count) package(s) with new releases" -ForegroundColor Yellow
Write-Host "Total new releases across all packages: $($packagesWithNewReleases | ForEach-Object { $_.release_count } | Measure-Object -Sum | Select-Object -ExpandProperty Sum)" -ForegroundColor Yellow

# Write the result to the output file
if ($result.Count -gt 0) {
    try {
        $result | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputJsonPath
        Write-Host "Output written to: $OutputJsonPath" -ForegroundColor Cyan
    }
    catch {
        Write-Error "Failed to write output file: $_"
        exit 1
    }
}
else {
    Write-Host "No differences found. No output file created." -ForegroundColor Green
}
