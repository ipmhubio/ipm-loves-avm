function Update-PackageVersionState
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage,

        [Parameter(Mandatory = $True, ParameterSetName = "SecureSasToken")]
        [ValidateNotNull()]
        [SecureString] $SecureSasToken,

        [Parameter(Mandatory = $True, ParameterSetName = "SasTokenFromEnvVariable")]
        [String] $SasTokenFromEnvironmentVariable,

        [Parameter(Mandatory = $True, ParameterSetName = "UnsecureSasToken")]
        [ValidateNotNullOrEmpty()]
        [String] $SasToken,

        [Parameter(Mandatory = $False)]
        [ValidateNotNullOrEmpty()]
        [String] $StateAccount = "ipmhubsponstor01weust",

        [Parameter(Mandatory = $False)]
        [ValidateNotNullOrEmpty()]
        [String] $StateTableName = "AvmPackageVersions",

        [Parameter(Mandatory = $False)]
        [Switch] $RunLocal = $false
    )

    try
    {
        Write-Log "Starting Update-PackageVersionState for package '$PackageName' version '$Version'" -Level "INFO"

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

        $BaseUri = "https://{0}.table.core.windows.net/" -f $StateAccount
        $partitionKey = $PackageName
        $rowKey = $Version.Replace(".", "-")  # Ensure valid rowkey format
        Write-Log "Using PartitionKey: '$partitionKey', RowKey: '$rowKey'" -Level "DEBUG"

        # Build entity URI for the specific entity
        $EntityUri = "{0}{1}(PartitionKey='{2}',RowKey='{3}')" -f $BaseUri, $StateTableName, $partitionKey, $rowKey

        # Ensure SAS token has proper format
        If (-not $SasToken.StartsWith("?"))
        {
            $SasToken = "?{0}" -f $SasToken
        }

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
            "Status" = $Status
            "LastUpdated" = [DateTime]::UtcNow.ToString("o")
        }

        # Add optional properties if they have values
        if ($PSBoundParameters.ContainsKey('ErrorMessage') -and $null -ne $ErrorMessage) {
            $entityProperties["ErrorMessage"] = $ErrorMessage
        }

        if ($PSBoundParameters.ContainsKey('published') -and $null -ne $published) {
            $entityProperties["Published"] = $published
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

        Write-Log "Successfully updated state for package '$PackageName' version '$Version' with status '$Status'" -Level "INFO"
        return $true
    }
    catch
    {
        $errorDetails = @{
            Message    = $_.Exception.Message
            Line       = $_.InvocationInfo.ScriptLineNumber
            ScriptName = $_.InvocationInfo.ScriptName
            StackTrace = $_.Exception.StackTrace
        } | ConvertTo-Json
        Write-Log "Failed to update package version state. Error details: $errorDetails" -Level "ERROR"
        return $false
    }
}

function Get-PackageVersionState
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $True, ParameterSetName = "SecureSasToken")]
        [ValidateNotNull()]
        [SecureString] $SecureSasToken,

        [Parameter(Mandatory = $True, ParameterSetName = "SasTokenFromEnvVariable")]
        [String] $SasTokenFromEnvironmentVariable,

        [Parameter(Mandatory = $True, ParameterSetName = "UnsecureSasToken")]
        [ValidateNotNullOrEmpty()]
        [String] $SasToken,

        [Parameter(Mandatory = $False)]
        [ValidateNotNullOrEmpty()]
        [String] $StateAccount = "ipmhubsponstor01weust",

        [Parameter(Mandatory = $False)]
        [ValidateNotNullOrEmpty()]
        [String] $StateTableName = "AvmPackageVersions",

        [Parameter(Mandatory = $False)]
        [Switch] $RunLocal = $false
    )

    Write-Log "Starting Get-PackageVersionState for package '$PackageName' version '$Version'" -Level "INFO"

    if ($RunLocal)
    {
        $StateTableName = "{0}{1}" -f "TEST", $StateTableName
        Write-Log "Running locally, using test table: $StateTableName" -Level "DEBUG"
    }

    If ($PSCmdlet.ParameterSetName -eq "SasTokenFromEnvVariable")
    {
      $SasToken = [System.Environment]::GetEnvironmentVariable($SasTokenFromEnvironmentVariable)
    }
    ElseIf ($PSCmdlet.ParameterSetName -eq "SecureSasToken")
    {
      $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureSasToken)
      $SasToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    }

    $BaseUri = "https://{0}.table.core.windows.net/" -f $StateAccount
    $PartitionKey = $PackageName
    $RowKey = $Version.Replace(".", "-")  # Ensure valid rowkey format

    # Create direct entity access URI using entity address format
    $EntityUri = "{0}{1}(PartitionKey='{2}',RowKey='{3}')" -f $BaseUri, $StateTableName, $PartitionKey, $RowKey

    $Headers = @{
      "x-ms-date" = [DateTime]::UtcNow.ToString("R")
      "Accept" = "application/json;odata=nometadata"
    }

    If (-not $SasToken.StartsWith("?"))
    {
      $SasToken = "?{0}" -f $SasToken
    }

    # Append SAS token to the entity URL
    $QueryUri = "{0}{1}" -f $EntityUri, $SasToken
    Write-Log ("Query URI: {0}" -f $QueryUri) -Level "DEBUG"

    try {
        $Response = Invoke-RestMethod -Uri $QueryUri -Method "Get" -Headers $Headers

        if ($Response) {
            $status = $Response.Status
            Write-Log "Found entry - Package: $PackageName, Version: $RowKey, Status: $status" -Level "DEBUG"
            return $status
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Log "No entry found for Package: $PackageName, Version: $RowKey" -Level "DEBUG"
        }
        else {
            Write-Log "Error querying table: $($_.Exception.Message)" -Level "WARN"
        }
    }

    return $false
}

function Get-PublishedPackages
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Cosmos.Table.CloudTable]$Table
    )

    Write-Log "Starting Get-PublishedPackages" -Level "INFO"
    Write-Log "Using table: $($Table.Name) in storage account: $($Table.ServiceClient.Credentials.AccountName)" -Level "DEBUG"

    # Query for all entries with Status = 'Published'
    $filter = "Status eq 'Published'"
    $query = [Microsoft.Azure.Cosmos.Table.TableQuery]::new()
    $query.FilterString = $filter

    try
    {
        $results = $Table.ExecuteQuery($query)
        $resultsCount = ($results | Measure-Object).Count
        Write-Log "Query returned $resultsCount published entries" -Level "DEBUG"

        # Extract distinct package names (PartitionKeys)
        $publishedPackages = $results |
            Select-Object -ExpandProperty PartitionKey -Unique |
                Sort-Object

        Write-Log "Found $($publishedPackages.Count) unique packages with published versions" -Level "INFO"
        return $publishedPackages
    }
    catch
    {
        $errorDetails = @{
            Message    = $_.Exception.Message
            Line       = $_.InvocationInfo.ScriptLineNumber
            ScriptName = $_.InvocationInfo.ScriptName
            StackTrace = $_.Exception.StackTrace
        } | ConvertTo-Json
        Write-Log "Failed to get published packages. Error details: $errorDetails" -Level "ERROR"
        return @()
    }
}

