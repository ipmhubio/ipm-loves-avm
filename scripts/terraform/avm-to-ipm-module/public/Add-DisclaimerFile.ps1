<#
.SYNOPSIS
    Creates a disclaimer file for AVM module packages.
.DESCRIPTION
    This function creates a DISCLAIMER.md file in the specified path, using a template
    where the package name is inserted in the appropriate places.
.PARAMETER Path
    The directory path where the DISCLAIMER.md file should be created.
.PARAMETER PackageName
    The name of the AVM package to be referenced in the disclaimer.
.EXAMPLE
    Add-DisclaimerFile -Path "C:\path\to\package" -PackageName "terraform-azurerm-avm-res-compute-virtualmachine"
#>
function Add-DisclaimerFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$PackageName
    )

    $disclaimerContent = @"
# Disclaimer

This package is a wrapper around the Microsoft AVM module [$PackageName](https://github.com/Azure/$PackageName), which is available under the MIT License. \
The original Microsoft AVM modules and their associated components are developed and maintained by Microsoft Corporation.\

Please see [docs page](https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/).

## Important Notes

- The source code and libraries included in this package are not created by IPMHub; they are derived from Microsoft's AVM modules.
- All trademarks, service marks, and logos associated with Microsoft are the property of Microsoft Corporation.
- This wrapper aims to provide additional functionality and convenience for users but does not modify or claim ownership of the original AVM modules.
- Users should refer to the official Microsoft documentation for comprehensive details regarding the AVM modules.

By using this package, you acknowledge and agree to these terms.

## License

This package is licensed under the MIT License. Please see the [LICENSE](LICENSE) file for more information.
"@

    $disclaimerPath = Join-Path -Path $Path -ChildPath "DISCLAIMER.md"

    try {
        Set-Content -Path $disclaimerPath -Value $disclaimerContent -Force
        Write-Log "Created DISCLAIMER.md file for $PackageName in $Path" -Level "INFO"
        return $true
    }
    catch {
        Write-Log "Failed to create DISCLAIMER.md file: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Export the function
Export-ModuleMember -Function Add-DisclaimerFile
