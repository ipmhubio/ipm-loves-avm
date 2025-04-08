function Update-ReleaseNotes {
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

        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [string]$ReleaseNotes,

        [Parameter(Mandatory = $true)]
        [DateTime]$CreatedAt,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [String] $StateAccount = "ipmhubsponstor01weust",

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [String] $StateTableName = "AvmPackageReleaseNotes",

        [Parameter(Mandatory = $false)]
        [Switch] $RunLocal = $false
    )

    try {
        Write-Log "Starting Update-ReleaseNotes for package '$PackageName' version '$Version'" -Level "INFO"

        if ([string]::IsNullOrEmpty($ReleaseNotes)) {
            Write-Log "Release notes are empty, using default message" -Level "INFO"
            $ReleaseNotes = "No release notes were published in the GitHub Release for this version."
        }

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
        $partitionKey = $PackageName
        $rowKey = $Version.Replace(".", "-")  # Ensure valid rowkey format

        # Build entity URI for the specific entity
        $EntityUri = "{0}{1}(PartitionKey='{2}',RowKey='{3}')" -f $BaseUri, $StateTableName, $partitionKey, $rowKey

        # Set common headers for all requests
        $Headers = @{
            "x-ms-date" = [DateTime]::UtcNow.ToString("R")
            "Accept" = "application/json;odata=nometadata"
        }

        # First check if entity exists by attempting to retrieve it
        $QueryUri = "{0}{1}" -f $EntityUri, $SasToken
        Write-Log "Querying for existing entity: $EntityUri" -Level "DEBUG"

        $entityExists = $false
        $etag = $null
        $existingEntity = $null

        try {
            $existingEntity = Invoke-RestMethod -Uri $QueryUri -Method "Get" -Headers $Headers
            $entityExists = $true
            $etag = $existingEntity["odata.etag"]
            Write-Log "Found existing entity with ETag: $etag" -Level "DEBUG"
        }
        catch {
            if ($_.Exception.Response.StatusCode -eq 404) {
                Write-Log "No existing entity found, will insert new entity" -Level "DEBUG"
            }
            else {
                throw  # Re-throw for other errors
            }
        }

        # Create entity payload with properties
        $entityProperties = @{
            "PartitionKey" = $partitionKey
            "RowKey" = $rowKey
        }

        # Handle properties based on entity existence
        if (!$entityExists) {
            # For new entity, set all values
            $entityProperties["ReleaseNotes"] = $ReleaseNotes
            $entityProperties["CreatedAt"] = $CreatedAt.ToString("o")
            $entityProperties["Version"] = $Version
        } else {
            # For existing entity, only update if values are provided
            if ($PSBoundParameters.ContainsKey('ReleaseNotes')) {
                $entityProperties["ReleaseNotes"] = $ReleaseNotes
            }
            if ($PSBoundParameters.ContainsKey('CreatedAt')) {
                $entityProperties["CreatedAt"] = $CreatedAt.ToString("o")
            }
            if ($PSBoundParameters.ContainsKey('Version')) {
                $entityProperties["Version"] = $Version
            }
        }

        $entityPayload = $entityProperties | ConvertTo-Json
        Write-Log "Created entity payload: $entityPayload" -Level "DEBUG"

        # URI for table entity operations
        $TableEntityUri = "{0}{1}{2}" -f $BaseUri, $StateTableName, $SasToken

        # Different approach based on entity existence
        if ($entityExists) {
            # Update existing entity
            $MergeUri = "{0}{1}" -f $EntityUri, $SasToken
            $MergeHeaders = $Headers.Clone()
            $MergeHeaders["If-Match"] = $etag
            $MergeHeaders["Content-Type"] = "application/json"

            Write-Log "Updating existing entity with MERGE operation" -Level "DEBUG"
            $response = Invoke-RestMethod -Uri $MergeUri -Method "MERGE" -Headers $MergeHeaders -Body $entityPayload
        }
        else {
            # Insert new entity
            $InsertHeaders = $Headers.Clone()
            $InsertHeaders["Content-Type"] = "application/json"

            Write-Log "Inserting new entity" -Level "DEBUG"
            $response = Invoke-RestMethod -Uri $TableEntityUri -Method "POST" -Headers $InsertHeaders -Body $entityPayload
        }

        Write-Log "Successfully updated release notes for $PackageName version $Version" -Level "INFO"
        return $true
    }
    catch {
        $errorDetails = @{
            Message    = $_.Exception.Message
            Line       = $_.InvocationInfo.ScriptLineNumber
            ScriptName = $_.InvocationInfo.ScriptName
            StackTrace = $_.Exception.StackTrace
        } | ConvertTo-Json
        Write-Log "Failed to update release notes: $errorDetails" -Level "ERROR"
        return $false
    }
}

function Get-CombinedReleaseNotes {
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

        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $true)]
        [string]$ModulePath,

        [Parameter(Mandatory = $false)]
        [string]$Version,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [String] $StateAccount = "ipmhubsponstor01weust",

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [String] $StateTableName = "AvmPackageReleaseNotes",

        [Parameter(Mandatory = $false)]
        [Switch] $RunLocal = $false
    )

    try {
        Write-Log "Getting combined release notes for package '$PackageName' up to version '$Version'" -Level "INFO"

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

        # Create query to get all entities for this partition key
        $filter = "PartitionKey eq '{0}'" -f $PackageName
        $encodedFilter = [System.Web.HttpUtility]::UrlEncode($filter)
        $QueryUri = "{0}{1}{2}&`$filter={3}" -f $BaseUri, $StateTableName, $SasToken, $encodedFilter

        $Headers = @{
            "x-ms-date" = [DateTime]::UtcNow.ToString("R")
            "Accept" = "application/json;odata=nometadata"
        }

        Write-Log "Querying for all versions of package: $PackageName" -Level "DEBUG"

        try {
            $response = Invoke-RestMethod -Uri $QueryUri -Method "Get" -Headers $Headers
            $results = $response.value
            Write-Log "Found $($results.Count) total versions for package '$PackageName'" -Level "DEBUG"
        }
        catch {
            Write-Log "Error querying table: $($_.Exception.Message)" -Level "ERROR"
            throw
        }

        if ($results.Count -eq 0) {
            Write-Log "No release notes found for package '$PackageName'" -Level "WARNING"
            # Create minimal release notes file
            $minimalNotes = "# Release History`n"
            $releaseNotesPath = Join-Path $ModulePath "RELEASENOTES.md"
            Set-Content -Path $releaseNotesPath -Value $minimalNotes -Force
            return $minimalNotes
        }

        # Filter versions if Version parameter is provided
        if ($Version) {
            $targetVersion = [Version]($Version.TrimStart('v'))
            $results = $results | Where-Object {
                if (![string]::IsNullOrEmpty($_.Version)) {
                    $currentVersion = [Version]($_.Version.TrimStart('v'))
                    $currentVersion -le $targetVersion
                } else {
                    $false
                }
            }
            Write-Log "Filtered to $($results.Count) versions up to $Version" -Level "DEBUG"
        }

        # Sort by CreatedAt date in reverse order (newest first)
        $sortedResults = $results | Where-Object { $_.CreatedAt } |
                          Sort-Object { [DateTime]::Parse($_.CreatedAt) } -Descending
        Write-Log "Sorted results by creation date (newest first)" -Level "DEBUG"

        # Combine release notes with newest first
        $combinedNotes = New-Object System.Text.StringBuilder

        [void]$combinedNotes.AppendLine("# Release History")
        [void]$combinedNotes.AppendLine("")

        foreach ($result in $sortedResults) {
            if ($result.ReleaseNotes -and $result.Version -and $result.CreatedAt) {
                $version = $result.Version
                $notes = $result.ReleaseNotes.Trim()
                $date = [DateTime]::Parse($result.CreatedAt).ToString("yyyy-MM-dd")

                Write-Log "Processing version $version from $date" -Level "DEBUG"
                [void]$combinedNotes.AppendLine("## Version $version - $date")
                [void]$combinedNotes.AppendLine("")
                [void]$combinedNotes.AppendLine($notes)
                [void]$combinedNotes.AppendLine("")
            }
        }

        $releaseNotes = $combinedNotes.ToString()

        # Write to the RELEASENOTES.md file in the module path
        $releaseNotesPath = Join-Path $ModulePath "RELEASENOTES.md"
        Set-Content -Path $releaseNotesPath -Value $releaseNotes -Force

        Write-Log "Successfully generated and saved combined release notes to $releaseNotesPath ($($releaseNotes.Length) characters)" -Level "INFO"
        return $releaseNotes
    }
    catch {
        $errorDetails = @{
            Message    = $_.Exception.Message
            Line       = $_.InvocationInfo.ScriptLineNumber
            ScriptName = $_.InvocationInfo.ScriptName
            StackTrace = $_.Exception.StackTrace
        } | ConvertTo-Json
        Write-Log "Failed to get combined release notes: $errorDetails" -Level "ERROR"
        throw
    }
}