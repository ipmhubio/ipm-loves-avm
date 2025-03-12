function Test-TerraformModule
{
    param (
        [string]$ModulePath
    )

    # Change to module directory
    $currentLocation = Get-Location
    try
    {
        Set-Location -Path $ModulePath

        # Run terraform init
        Write-Log "Running terraform init for $ModulePath..." -Level "INFO"
        $initProcess = Start-Process -FilePath "terraform" -ArgumentList "init", "-no-color" -NoNewWindow -PassThru -Wait -RedirectStandardOutput "terraform_init.log" -RedirectStandardError "terraform_init_error.log"

        if ($initProcess.ExitCode -ne 0)
        {
            Write-Log "Terraform init failed for $ModulePath" -Level "ERROR"
            return $false
        }

        # Run terraform validate
        Write-Log "Running terraform validate for $ModulePath..." -Level "INFO"
        $validateProcess = Start-Process -FilePath "terraform" -ArgumentList "validate", "-no-color" -NoNewWindow -PassThru -Wait -RedirectStandardOutput "terraform_validate.log" -RedirectStandardError "terraform_validate_error.log"

        if ($validateProcess.ExitCode -ne 0)
        {
            Write-Log "Terraform validate failed for $ModulePath" -Level "ERROR"
            return $false
        }

        # Run terraform fmt
        Write-Log "Running terraform fmt for $ModulePath..." -Level "INFO"
        $fmtProcess = Start-Process -FilePath "terraform" -ArgumentList "fmt", "-no-color", "-recursive" -NoNewWindow -PassThru -Wait

        #remove the .terraform directory
        Remove-Item -Path ".terraform" -Recurse -Force

        # fmt returns 0 if no changes were made, 1 if changes were made, and 2+ if there was an error
        if ($fmtProcess.ExitCode -gt 1)
        {
            Write-Log "Terraform fmt encountered errors for $ModulePath" -Level "ERROR"
            return $false
        }

        return $true
    }
    catch
    {
        Write-Log "Error testing Terraform module $ModulePath : $_" -Level "ERROR"
        return $false
    }
    finally
    {
        # Return to original location
        Set-Location -Path $currentLocation
    }
}