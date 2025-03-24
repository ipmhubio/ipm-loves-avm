function Update-PackageVersionState
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Cosmos.Table.CloudTable]$Table,

        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage
    )

    try
    {
        Write-Log "Starting Update-PackageVersionState for package '$PackageName' version '$Version'" -Level "INFO"
        Write-Log "Using table: $($Table.Name) in storage account: $($Table.ServiceClient.Credentials.AccountName)" -Level "DEBUG"

        $partitionKey = $PackageName
        $rowKey = $Version.Replace(".", "-")  # Ensure valid rowkey format
        Write-Log "Using PartitionKey: '$partitionKey', RowKey: '$rowKey'" -Level "DEBUG"

        # First try to retrieve the existing entity
        $retrieveOperation = [Microsoft.Azure.Cosmos.Table.TableOperation]::Retrieve($partitionKey, $rowKey)
        $existingEntity = $Table.Execute($retrieveOperation).Result

        # Create new entity
        $entity = New-Object -TypeName "Microsoft.Azure.Cosmos.Table.DynamicTableEntity" -ArgumentList $partitionKey, $rowKey

        # Only add properties that have values
        if ($Status)
        {
            $entity.Properties.Add("Status", $Status)
        }

        # LastUpdated is always set on updates
        $entity.Properties.Add("LastUpdated", [DateTime]::UtcNow)

        if ($PSBoundParameters.ContainsKey('ErrorMessage') -and $null -ne $ErrorMessage)
        {
            $entity.Properties.Add("ErrorMessage", $ErrorMessage)
        }

        Write-Log "Created entity with properties: $($entity.Properties | ConvertTo-Json)" -Level "DEBUG"

        # Choose operation based on whether entity exists
        if ($null -eq $existingEntity)
        {
            Write-Log "No existing entity found, using InsertOrMerge" -Level "DEBUG"
            $operation = [Microsoft.Azure.Cosmos.Table.TableOperation]::InsertOrMerge($entity)
        }
        else
        {
            Write-Log "Existing entity found, using Merge with ETag" -Level "DEBUG"
            $entity.ETag = $existingEntity.ETag
            $operation = [Microsoft.Azure.Cosmos.Table.TableOperation]::Merge($entity)
        }

        Write-Log "Executing operation..." -Level "DEBUG"

        $result = $Table.Execute($operation)
        Write-Log "Operation completed with status code: $($result.HttpStatusCode)" -Level "DEBUG"

        if ($result.HttpStatusCode -ge 200 -and $result.HttpStatusCode -lt 300)
        {
            Write-Log "Successfully updated state for package '$PackageName' version '$Version' with status '$Status'" -Level "INFO"
            Write-Log "ETag: $($result.Etag), Timestamp: $($result.Timestamp)" -Level "DEBUG"
            return $true
        }
        else
        {
            Write-Log "Operation completed but returned unexpected status code: $($result.HttpStatusCode)" -Level "WARN"
            return $false
        }
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
        [Microsoft.Azure.Cosmos.Table.CloudTable]$Table,

        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    Write-Log "Starting Get-PackageVersionState for package '$PackageName' version '$Version'" -Level "INFO"
    Write-Log "Using table: $($Table.Name) in storage account: $($Table.ServiceClient.Credentials.AccountName)" -Level "DEBUG"

    $rowKey = $Version.Replace(".", "-")
    $filter = "(PartitionKey eq '$PackageName') and (RowKey eq '$rowKey')"
    Write-Log "Executing query with filter: $filter" -Level "DEBUG"

    $query = [Microsoft.Azure.Cosmos.Table.TableQuery]::new()
    $query.FilterString = $filter
    $results = $Table.ExecuteQuery($query)
    Write-Log "Query returned $($results.Count) results" -Level "INFO"

    if ($results.Count -gt 0)
    {
        $status = $results[0].Properties["Status"].StringValue
        Write-Log "Found entry - Package: $PackageName, Version: $rowKey, Status: $status" -Level "DEBUG"
        return $status
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

