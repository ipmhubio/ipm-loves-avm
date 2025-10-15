function New-IpmPackageName
{
  [CmdletBinding()]
  [OutputType([string])]
  param (
    [Parameter(Mandatory = $true)]
    [string]$TerraformName
  )


  # Remove common prefixes from Terraform module names
  $ipmName = $TerraformName -replace "terraform-azurerm-avm-res-", ""
  $ipmName = $ipmName -replace "terraform-avm-azurerm-res-", ""

  # Check if name is longer than 30 characters (for backward compatibility)
  if ($ipmName.Length -gt 30)
  {
    Write-Log "Package name $ipmName is more than 30 characters. Checking for existing conversion." -Level "INFO"
    $convertedPackageName = Convert-PackageName -PackageName $ipmName
    if ($convertedPackageName -ne $false)
    {
      # Use existing conversion for backward compatibility
      $ipmName = $convertedPackageName
      Write-Log "Used existing conversion: Terraform name '$TerraformName' to IPM name '$ipmName'" -Level "INFO"
      return $ipmName
    }
    else
    {
      # No existing conversion found, check if it exceeds new 64-character limit
      if ($ipmName.Length -gt 64)
      {
        Write-Log "Package name $ipmName is more than 64 characters and no conversion exists." -Level "ERROR"
        throw "Package name $ipmName is more than 64 characters and no conversion exists in settings.jsonc."
      }
      else
      {
        Write-Log "Package name $ipmName is between 30-64 characters, using as-is since no existing conversion found." -Level "INFO"
      }
    }
  }

  return $ipmName
}
