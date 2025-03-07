function Get-NewReleases {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$GithubToken,

        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Cosmos.Table.CloudTable]$Table
    )

    Write-Log "Identifying new packages and releases..."
    $newReleases = @()

    try {
        # Set up GitHub API headers
        $headers = @{
            'Accept' = 'application/vnd.github+json'
            'Authorization' = "Bearer $GithubToken"
        }

        # Search for AVM repos
        $searchUrl = "https://api.github.com/search/repositories?q=org:azure+terraform-azurerm-avm-res-+in:name&per_page=100"
        $repos = Invoke-RestMethod -Uri $searchUrl -Headers $headers -Method Get

        foreach ($repo in $repos.items) {
            $repoName = $repo.name
            Write-Log "Checking releases for $repoName..." -Level "INFO"

            # Get all releases for this repository
            $releasesUrl = "https://api.github.com/repos/Azure/$repoName/releases"
            $releases = Invoke-RestMethod -Uri $releasesUrl -Headers $headers -Method Get

            foreach ($release in $releases) {
                $version = if ($release.tag_name.StartsWith('v')) {
                    $release.tag_name.Substring(1)
                } else {
                    $release.tag_name
                }

                # Check if this version exists in the state table
                $existingState = Get-PackageVersionState -Table $Table -PackageName $repoName -Version $version

                if (-not $existingState -or $existingState.Status -eq "Failed") {
                    $newReleases += [PSCustomObject]@{
                        name = $repoName
                        url = $repo.html_url
                        version = $version
                        published_at = $release.published_at
                        tarball_url = $release.tarball_url
                    }
                }
            }

            # Add a small delay to avoid rate limiting
            Start-Sleep -Milliseconds 500
        }

        $newPackageCount = ($newReleases | Select-Object -Property name -Unique).Count
        $newVersionCount = $newReleases.Count

        Write-Log "Found $newPackageCount packages with $newVersionCount new releases" -Level "SUCCESS"
        return $newReleases
    }
    catch {
        Write-Log "Error identifying new releases: $_" -Level "ERROR"
        throw
    }
}
