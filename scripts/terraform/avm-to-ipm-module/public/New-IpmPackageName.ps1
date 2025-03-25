function New-IpmPackageName
{
  [CmdletBinding()]
  [OutputType([string])]
  param (
    [Parameter(Mandatory = $true)]
    [string]$TerraformName
  )

  try
  {
    # Remove common prefixes from Terraform module names
    $ipmName = $TerraformName -replace "terraform-azurerm-avm-res-", ""
    $ipmName = $ipmName -replace "terraform-avm-azurerm-res-", ""

    # Additional transformations can be added here if needed
    # For example, replacing hyphens with underscores, etc.
    if ($ipmName.Length -gt 30)
    {
      Write-Log "Package name $ipmName is more than 30 characters. Trimming to 30 characters." -Level "INFO"
      $convertedPackageName = Convert-PackageName -PackageName $ipmName
      if ($convertedPackageName -eq $false)
      {
        return [PSCustomObject]@{
          Success = $false
          Message = "Failed to convert package name: $PackageName"
        }
      }
      $ipmName = $convertedPackageName
      Write-Log "Converted Terraform name '$TerraformName' to IPM name '$ipmName'" -Level "INFO"
      return $ipmName
    }
  }
  catch
  {
    Write-Log "Error converting Terraform name to IPM name: $($_.Exception.Message)" -Level "ERROR"
    return $false
  }
  return $ipmName
}
