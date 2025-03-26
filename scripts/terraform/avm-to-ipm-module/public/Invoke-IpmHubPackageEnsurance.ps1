Function Invoke-IpmHubPackageEnsurance
{
  [OutputType([PsCustomObject[]])]
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $True)]
    [PsCustomObject[]] $Packages,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [String] $PackageCreationApi,

    [Parameter(Mandatory = $False)]
    [bool]$LocalRun = $False
  )

  Begin
  {
    "{0} - START" -f $MyInvocation.MyCommand | Write-Verbose
    Write-Log "Ensuring that all packages exists within IPMHub..." -Level "INFO"
    Write-Log "Local run: $LocalRun" -Level "INFO"
  }

  Process
  {

    # Log the package data for troubleshooting
    Write-Log "Package data to process: $($PackageData.Count) packages" -Level "INFO"

    $PackageData = [Array] ($Packages | ForEach-Object {
      @{
        packageName = $_.Name
        description = ($_.Description ?? "")
        descriptionLang = ($_.descriptionLang ?? "en")
        projectUri = ($_.projectUri ?? "https://ipmhub.io/avm-terraform")
      }
    }) ?? @()

    if ($LocalRun)
    {
      Write-Log "Local run detected - Mocking API response"
      $Response = $PackageData | ForEach-Object {
        $PackageName = $_.packageName
        Write-Log "Processing package $PackageName..." -Level "INFO"

        # Create a mock response that mimics the API format with statusCode
        [PSCustomObject]@{
          packageName   = $PackageName
          latestVersion = "0.1.0" # Mock version
          versions      = @("0.1.0") # Mock versions array
          statusCode    = Get-Random -Minimum 200 -Maximum 201 # Random between 200 (exists) and 201 (created)
        }
      }
    }
    else
    {
      write-log "Sending package creation request to IPMHub API" -level "INFO"
      $Headers = @{ "Content-Type" = "application/json" }
      $Payload = @{ organizationName = "avm-terraform"; packages = $PackageData } | ConvertTo-Json -Depth 10
      write-log "Payload for IPMHub API: $Payload " -level "DEBUG"
      $Response = Invoke-RestMethod -Uri $PackageCreationApi -Method "Post" -Headers $Headers -Body $Payload
      $Response
    }
    write-log "Received response from IPMHub API: $($Response | ConvertTo-Json -Depth 10)" -level "INFO"

    # Process each package response individually to create a detailed output
    $ProcessedResponse = $Response | ForEach-Object {
      $statusMsg = if ($_.statusCode -eq 201) { "created" } else { "already exists" }
      [PSCustomObject]@{
        packageName   = $_.packageName
        status        = $statusMsg
        statusCode    = $_.statusCode
        latestVersion = $_.latestVersion
        versions      = $_.versions
        message       = "Package $($_.packageName) $($statusMsg)" + $(if ($_.latestVersion) { " (latest version: $($_.latestVersion))" } else { "" })
      }
    }

    # Check for errors in the response - handle both single and array responses
    $hasErrors = $false
    if ($Response -is [Array]) {
      # For array responses, check each item
      $hasErrors = ($Response | Where-Object { $_.statusCode -ne 200 -and $_.statusCode -ne 201 }).Count -gt 0
    } else {
      # For single object response, check directly
      $hasErrors = $Response.statusCode -ne 200 -and $Response.statusCode -ne 201
    }

    if ($hasErrors) {
      Write-Log "Error in response from IPMHub API: $($Response | ConvertTo-Json -Depth 10)" -Level "ERROR"
      throw "Failed to ensure packages in IPMHub"
    }

    # Return the processed response for further state updates
    return $ProcessedResponse
  }

  End
  {
    "{0} - END" -f $MyInvocation.MyCommand | Write-Verbose
  }
}