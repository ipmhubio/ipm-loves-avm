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
    [String] $OrganizationName
  )

  Begin
  {
    "{0} - START" -f $MyInvocation.MyCommand | Write-Verbose
  }

  Process
  {
    $PackageData = [Array] ($Packages | ForEach-Object {
        @{
          packageName     = $_.Name
          description     = ($_.Description ?? "").Replace("This module deploys", "This Terraform AVM module deploys")
          descriptionLang = "en"
          projectUri      = "https://ipmhub.io/avm-terraform"
        }
      }) ?? @()

    $Headers = @{ "Content-Type" = "application/json" }
    $Payload = @{
      organizationName = $OrganizationName
      packages         = $PackageData
    } | ConvertTo-Json -Depth 10

    $Response = Invoke-RestMethod -Uri $PackageCreationApi -Method "Post" -Headers $Headers -Body $Payload
    $Response
  }

  End
  {
    "{0} - END" -f $MyInvocation.MyCommand | Write-Verbose
  }
}