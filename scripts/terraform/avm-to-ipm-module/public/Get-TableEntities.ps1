function Get-TableEntities
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Cosmos.Table.CloudTable]$Table,

        [Parameter(Mandatory = $false)]
        [string]$Filter
    )

    try
    {
        Write-Log "Starting Get-TableEntities" -Level "INFO"
        Write-Log "Using table: $($Table.Name) in storage account: $($Table.ServiceClient.Credentials.AccountName)" -Level "DEBUG"

        # Create query
        $query = [Microsoft.Azure.Cosmos.Table.TableQuery]::new()

        # Apply filter if provided
        if (-not [string]::IsNullOrEmpty($Filter)) {
            $query.FilterString = $Filter
            Write-Log "Executing query with filter: $Filter" -Level "DEBUG"
        } else {
            Write-Log "Executing query without filter to get all entries" -Level "DEBUG"
        }

        # Execute query
        $results = $Table.ExecuteQuery($query)
        $resultsCount = ($results | Measure-Object).Count
        Write-Log "Query returned $resultsCount entries" -Level "DEBUG"

        # Convert table entities to PSCustomObjects
        $entities = @()
        foreach ($result in $results)
        {
            $entity = [PSCustomObject]@{
                PartitionKey = $result.PartitionKey
                RowKey = $result.RowKey
                ETag = $result.ETag
                Timestamp = $result.Timestamp
            }

            # Add all properties from the entity
            foreach ($prop in $result.Properties.Keys)
            {
                $propValue = $null

                # Extract the right value based on property type
                switch ($result.Properties[$prop].PropertyType)
                {
                    "String" { $propValue = $result.Properties[$prop].StringValue }
                    "DateTime" { $propValue = $result.Properties[$prop].DateTime }
                    "Int32" { $propValue = $result.Properties[$prop].Int32Value }
                    "Int64" { $propValue = $result.Properties[$prop].Int64Value }
                    "Boolean" { $propValue = $result.Properties[$prop].BooleanValue }
                    "Double" { $propValue = $result.Properties[$prop].DoubleValue }
                    "Guid" { $propValue = $result.Properties[$prop].GuidValue }
                    "Binary" { $propValue = $result.Properties[$prop].BinaryValue }
                    default { $propValue = $result.Properties[$prop].PropertyAsObject }
                }

                Add-Member -InputObject $entity -MemberType NoteProperty -Name $prop -Value $propValue -Force
            }

            $entities += $entity
        }

        Write-Log "Successfully converted $resultsCount table entities to PSCustomObjects" -Level "INFO"
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
