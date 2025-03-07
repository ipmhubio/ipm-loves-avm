# GitHub API script to find all terraform-azurerm-avm repos in the Azure organization and list their releases
# Requires a GitHub Personal Access Token to avoid rate limiting

param(
    [Parameter(Mandatory=$true)]
    [string]$GithubToken
)

# Function to handle pagination for GitHub API
function Get-GitHubApiResults {
    param (
        [string]$Url,
        [string]$Token
    )

    $headers = @{
        'Accept' = 'application/vnd.github+json'
        'Authorization' = "Bearer $Token"
    }

    $allResults = @()
    $currentUrl = $Url

    while ($null -ne $currentUrl) {
        $response = Invoke-RestMethod -Uri $currentUrl -Headers $headers -Method Get

        if ($response.items) {
            # Search API format
            $allResults += $response.items
        } else {
            # Regular list API format
            $allResults += $response
        }

        # Check for pagination in the Link header
        # Check for pagination in the Link header
        $currentUrl = $null

        # For Invoke-RestMethod in PowerShell, we need to check the Headers differently
        if ($response.Headers -and $response.Headers.Link) {
            $linkHeader = $response.Headers.Link
            $links = $linkHeader -split ','
            foreach ($link in $links) {
                if ($link -match '<([^>]+)>;\s*rel="next"') {
                    $currentUrl = $matches[1]
                    break
                }
            }
        }
    }

    return $allResults
}

# Step 1: Find all repos starting with terraform-azurerm-avm in the Azure organization
$searchUrl = "https://api.github.com/search/repositories?q=org:azure+terraform-azurerm-avm-res-+in:name&per_page=100"
Write-Host "Searching for repositories matching 'terraform-azurerm-avm' in Azure organization..."
$repos = Get-GitHubApiResults -Url $searchUrl -Token $GithubToken

# Add a small delay between requests to avoid hitting rate limits
Start-Sleep -Milliseconds 500

if ($repos.Count -eq 0) {
    Write-Warning "No repositories found matching the criteria."
    exit
}

Write-Host "Found $($repos.Count) repositories. Gathering release information..."

# Step 2: Get releases for each repository
$results = @()

foreach ($repo in $repos) {
    $repoName = $repo.name
    $repoUrl = $repo.html_url
    Write-Host "Processing repository: $repoName"

    # Get releases for this repository directly without using the helper function
    $headers = @{
        'Accept' = 'application/vnd.github+json'
        'Authorization' = "Bearer $GithubToken"
    }

    $releasesUrl = "https://api.github.com/repos/Azure/$repoName/releases?per_page=100"
    Write-Host "Requesting: $releasesUrl"

    try {
        $releases = Invoke-RestMethod -Uri $releasesUrl -Headers $headers -Method Get
        Write-Host "Found $($releases.Count) releases"

        # Debug - show first release if available
        if ($releases.Count -gt 0) {
            Write-Host "First release tag: $($releases[0].tag_name)"
        }
    }
    catch {
        Write-Host "Error retrieving releases: $_"
        $releases = @()
    }

    # Add a small delay between requests to avoid hitting rate limits
    Start-Sleep -Milliseconds 500

    # Extract detailed version information
    $releaseDetails = @()

    # Check if we got any releases
    if ($releases -and $releases.Count -gt 0) {
        foreach ($release in $releases) {
            Write-Host "Processing release with tag: $($release.tag_name)"

            # Create a new object with the desired properties
            $releaseInfo = [PSCustomObject]@{
                version = if ($release.tag_name -and $release.tag_name.StartsWith('v')) {
                    $release.tag_name.Substring(1)
                } else {
                    $release.tag_name
                }
                published_at = $release.published_at
                name = $release.name
                draft = $release.draft
                tarball_url = $release.tarball_url
                html_url = $release.html_url
                created_at = $release.created_at
                body = $release.body
            }

            $releaseDetails += $releaseInfo
        }
    }

    # Add to results
    $repoInfo = [PSCustomObject]@{
        name = $repoName
        url = $repoUrl
        releases = @($releaseDetails)
        release_count = $releaseDetails.Count
    }

    $results += $repoInfo
}

# Step 3: Convert to JSON and output
$jsonOutput = $results | ConvertTo-Json -Depth 4

# Output to console
Write-Host "Results:"
$jsonOutput

# Optionally write to file
$outputPath = "azure-terraform-avm-releases.json"
$jsonOutput | Out-File -FilePath $outputPath
Write-Host "Results saved to $outputPath"