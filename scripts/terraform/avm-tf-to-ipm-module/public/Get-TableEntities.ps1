function Get-TableEntities
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "SecureSasToken")]
        [ValidateNotNull()]
        [SecureString] $SecureSasToken,

        [Parameter(Mandatory = $true, ParameterSetName = "SasTokenFromEnvVariable")]
        [String] $SasTokenFromEnvironmentVariable,

        [Parameter(Mandatory = $true, ParameterSetName = "UnsecureSasToken")]
        [ValidateNotNullOrEmpty()]
        [String] $SasToken,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [String] $StateAccount = "ipmhubsponstor01weust",

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [String] $StateTableName = "AvmPackageVersions",

        [Parameter(Mandatory = $false)]
        [string]$Filter,

        [Parameter(Mandatory = $false)]
        [Switch] $RunLocal = $false
    )

    try
    {
        Write-Log "Starting Get-TableEntities" -Level "INFO"

        if ($RunLocal)
        {
            $StateTableName = "{0}{1}" -f "TEST", $StateTableName
            Write-Log "Running locally, using test table: $StateTableName" -Level "DEBUG"
        }

        # Parse SAS token from the appropriate parameter
        If ($PSCmdlet.ParameterSetName -eq "SasTokenFromEnvVariable")
        {
            $SasToken = [System.Environment]::GetEnvironmentVariable($SasTokenFromEnvironmentVariable)
        }
        ElseIf ($PSCmdlet.ParameterSetName -eq "SecureSasToken")
        {
            $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureSasToken)
            $SasToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        }

        # Ensure SAS token has proper format
        If (-not $SasToken.StartsWith("?"))
        {
            $SasToken = "?{0}" -f $SasToken
        }

        $BaseUri = "https://{0}.table.core.windows.net/" -f $StateAccount
        Write-Log "Using table: $StateTableName in storage account: $StateAccount" -Level "DEBUG"

        # Set common headers for all requests
        $Headers = @{
            "x-ms-date" = [DateTime]::UtcNow.ToString("R")
            "Accept" = "application/json;odata=nometadata"
        }

        # Build query URI
        $QueryUri = "{0}{1}{2}" -f $BaseUri, $StateTableName, $SasToken

        # Apply filter if provided
        if (-not [string]::IsNullOrEmpty($Filter)) {
            $encodedFilter = [System.Web.HttpUtility]::UrlEncode($Filter)
            $QueryUri = "{0}&`$filter={1}" -f $QueryUri, $encodedFilter
            Write-Log "Executing query with filter: $Filter" -Level "DEBUG"
        } else {
            Write-Log "Executing query without filter to get all entries" -Level "DEBUG"
        }

        # Execute query
        $response = Invoke-RestMethod -Uri $QueryUri -Method "Get" -Headers $Headers
        $results = $response.value
        $resultsCount = ($results | Measure-Object).Count
        Write-Log "Query returned $resultsCount entries" -Level "DEBUG"

        # Results from REST API are already in proper format with properties as direct members
        # Just pass through since they're already deserialized as PSCustomObjects

        # Include odata.etag as ETag property if needed for consistency
        $entities = $results | ForEach-Object {
            if ($_.'odata.etag') {
                $_ | Add-Member -MemberType NoteProperty -Name 'ETag' -Value $_.'odata.etag' -Force
            }
            $_
        }

        Write-Log "Successfully processed $resultsCount table entities" -Level "INFO"
        return $entities
    }
    catch
    {
        $errorDetails = @{
            Message    = $_.Exception.Message
            Line       = $_.InvocationInfo.ScriptLineNumber
            ScriptName = $_.InvocationInfo.ScriptName
            StackTrace = $_.Exception.StackTrace
        } | ConvertTo-Json
        Write-Log "Failed to get table entities. Error details: $errorDetails" -Level "ERROR"
        return @()
    }
}