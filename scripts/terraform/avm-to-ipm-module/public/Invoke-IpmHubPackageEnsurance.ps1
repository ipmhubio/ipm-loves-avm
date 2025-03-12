Function Invoke-IpmHubPackageEnsurance
{
  [OutputType([PsCustomObject[]])]
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory = $True)]
    [PsCustomObject[]] $Packages,

    [Parameter(Mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [String] $PackageCreationApi,

    [Parameter(Mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [String] $OrganizationName,

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
    $PackageData = [Array] ($Packages | ForEach-Object {
        $PackageName = $_.Name
        $PackageName = $PackageName -replace "terraform-azurerm-avm-res-", ""
        $PackageName = $PackageName -replace "terraform-avm-azurerm-res-", ""

        Write-Log "Processing package $PackageName..." -Level "INFO"

        if ([string]::IsNullOrEmpty($PackageName))
        {
          Write-Log "Package name cannot be empty" -Level "ERROR"
          continue
        }

        if ($PackageName.Length -gt 36)
        {
          Write-Log "Package name $PackageName is more than 36 characters. Trimming to 36 characters." -Level "INFO"
          $convertedPackageName = Convert-PackageName -PackageName $PackageName
          if ($convertedPackageName -eq $false)
          {
            Write-Log "Failed to convert package name: $PackageName" -Level "ERROR"
            continue
          }
          $PackageName = $convertedPackageName
        }

        @{
          packageName     = $PackageName
          description     = "This Terraform AVM module deploys $($PackageName)"
          descriptionLang = "en"
          projectUri      = "https://ipmhub.io/avm-terraform"
        }
      }) ?? @()


    $Headers = @{ "Content-Type" = "application/json" }
    $Payload = @{
      organizationName = $OrganizationName
      packages         = $PackageData
    } | ConvertTo-Json -Depth 10

    if ($LocalRun)
    {
      Write-Log "Local run detected - Mocking API response"
      $Response = $PackageData | ForEach-Object {
        [PSCustomObject]@{
          packageName = $_.packageName
          status      = "created"
          message     = "Package created successfully (mocked)"
        }
      }
    }
    else
    {
      write-log "Sending package creation request to IPMHub API" -level "INFO"
      $Response = Invoke-RestMethod -Uri $PackageCreationApi -Method "Post" -Headers $Headers -Body $Payload
    }
    write-log "Received response from IPMHub API: $($Response | ConvertTo-Json -Depth 10)" -level "INFO"
    $Response
  }

  End
  {
    "{0} - END" -f $MyInvocation.MyCommand | Write-Verbose
  }
}