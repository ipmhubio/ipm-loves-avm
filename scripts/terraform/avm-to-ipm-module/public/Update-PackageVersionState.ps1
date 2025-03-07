function Update-PackageVersionState {
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

    try {
        Write-Log "Starting Update-PackageVersionState for package '$PackageName' version '$Version'" -Level "INFO"
        Write-Log "Using table: $($Table.Name) in storage account: $($Table.ServiceClient.Credentials.AccountName)" -Level "DEBUG"

        $partitionKey = $PackageName
        $rowKey = $Version.Replace(".", "-")  # Ensure valid rowkey format
        Write-Log "Using PartitionKey: '$partitionKey', RowKey: '$rowKey'" -Level "DEBUG"

        # Create a new entity
        $entity = New-Object -TypeName "Microsoft.Azure.Cosmos.Table.DynamicTableEntity" -ArgumentList $partitionKey, $rowKey
        $entity.Properties.Add("Status", $Status)
        $entity.Properties.Add("LastUpdated", [DateTime]::UtcNow)
        $entity.Properties.Add("ErrorMessage", $ErrorMessage)

        Write-Log "Created entity with Status: '$Status', LastUpdated: '$([DateTime]::UtcNow)', ErrorMessage: '$ErrorMessage'" -Level "DEBUG"

        # Insert or merge the entity
        $operation = [Microsoft.Azure.Cosmos.Table.TableOperation]::InsertOrMerge($entity)
        Write-Log "Executing InsertOrMerge operation..." -Level "DEBUG"

        $result = $Table.Execute($operation)
        Write-Log "Operation completed with status code: $($result.HttpStatusCode)" -Level "DEBUG"

        if ($result.HttpStatusCode -ge 200 -and $result.HttpStatusCode -lt 300) {
            Write-Log "Successfully updated state for package '$PackageName' version '$Version' with status '$Status'" -Level "INFO"
            Write-Log "ETag: $($result.Etag), Timestamp: $($result.Timestamp)" -Level "DEBUG"
            return $true
        } else {
            Write-Log "Operation completed but returned unexpected status code: $($result.HttpStatusCode)" -Level "WARN"
            return $false
        }
    }
    catch {
        $errorDetails = @{
            Message = $_.Exception.Message
            Line = $_.InvocationInfo.ScriptLineNumber
            ScriptName = $_.InvocationInfo.ScriptName
            StackTrace = $_.Exception.StackTrace
        } | ConvertTo-Json
        Write-Log "Failed to update package version state. Error details: $errorDetails" -Level "ERROR"
        return $false
    }
}

function Get-PackageVersionState {
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

    # Convert version dots to hyphens for RowKey
    $rowKey = $Version.Replace(".", "-")

    # Create filter
    $filter = "(PartitionKey eq '$PackageName') and (RowKey eq '$rowKey')"
    Write-Log "Executing query with filter: $filter" -Level "DEBUG"

    # Execute query
    $query = [Microsoft.Azure.Cosmos.Table.TableQuery]::new()
    $query.FilterString = $filter
    $results = $Table.ExecuteQuery($query)
    Write-Log "Query returned $($results.Count) results" -Level "INFO"

    if ($results.Count -gt 0) {
        $result = @{
            Success = $true
            Done = $false
            Message = ""
            Status = $results[0].Status
            LastUpdated = $results[0].LastUpdated
            ErrorMessage = $results[0].ErrorMessage
        }

        if ($result.Status -eq "Published") {
            $result.Done = $true
        }

        Write-Log "Found entry - Package: $PackageName, Version: $rowKey, Status: $($result.Status)" -Level "DEBUG"
        return $result
    }

    return $null
}