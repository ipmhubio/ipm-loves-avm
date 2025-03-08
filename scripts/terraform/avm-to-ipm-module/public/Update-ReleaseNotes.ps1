function Update-ReleaseNotes {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Cosmos.Table.CloudTable]$table,

        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$ReleaseNotes,

        [Parameter(Mandatory = $true)]
        [DateTime]$CreatedAt
    )

    try {
        Write-Log "Starting Update-ReleaseNotes for package '$PackageName' version '$Version'" -Level "INFO"

        $partitionKey = $PackageName
        $rowKey = $Version.Replace(".", "-")

        # Retrieve existing entity if it exists
        $retrieveOperation = [Microsoft.Azure.Cosmos.Table.TableOperation]::Retrieve($partitionKey, $rowKey)
        $existingEntity = $table.Execute($retrieveOperation).Result

        if ($null -eq $existingEntity) {
            Write-Log "Creating new entity for $PackageName version $Version" -Level "DEBUG"
            $entity = New-Object -TypeName "Microsoft.Azure.Cosmos.Table.DynamicTableEntity" -ArgumentList $partitionKey, $rowKey
            $entity.Properties["ReleaseNotes"] = $ReleaseNotes
            $entity.Properties["CreatedAt"] = $CreatedAt
            $entity.Properties["Version"] = $Version
        } else {
            Write-Log "Updating existing entity for $PackageName version $Version" -Level "DEBUG"
            $entity = $existingEntity
            # Only update if values are provided
            if ($PSBoundParameters.ContainsKey('ReleaseNotes')) {
                $entity.Properties["ReleaseNotes"] = $ReleaseNotes
            }
            if ($PSBoundParameters.ContainsKey('CreatedAt')) {
                $entity.Properties["CreatedAt"] = $CreatedAt
            }
            if ($PSBoundParameters.ContainsKey('Version')) {
                $entity.Properties["Version"] = $Version
            }
        }

        $operation = [Microsoft.Azure.Cosmos.Table.TableOperation]::InsertOrMerge($entity)
        $result = $table.Execute($operation)

        Write-Log "Successfully updated release notes for $PackageName version $Version" -Level "INFO"
        return $true
    }
    catch {
        Write-Log "Failed to update release notes: $_" -Level "ERROR"
        return $false
    }
}

function Get-CombinedReleaseNotes {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Cosmos.Table.CloudTable]$table, # Renamed parameter to be more specific

        [Parameter(Mandatory = $true)]
        [string]$PackageName
    )

    try {
        Write-Log "Getting combined release notes for package '$PackageName'" -Level "INFO"

        # Query all versions for this package
        $query = [Microsoft.Azure.Cosmos.Table.TableQuery]::new()
        # Update query to use simple partition key
        $filter = "PartitionKey eq '$PackageName'"
        $query.FilterString = $filter

        $results = $table.ExecuteQuery($query)

        # Sort by CreatedAt date
        $sortedResults = $results | Sort-Object { $_.Properties["CreatedAt"].DateTime }

        # Combine release notes in chronological order
        $combinedNotes = New-Object System.Text.StringBuilder

        [void]$combinedNotes.AppendLine("# Release History")
        [void]$combinedNotes.AppendLine("")

        foreach ($result in $sortedResults) {
            if ($result.Properties["ReleaseNotes"]) {
                $version = $result.Properties["Version"].StringValue
                $notes = $result.Properties["ReleaseNotes"].StringValue
                $date = $result.Properties["CreatedAt"].DateTime.ToString("yyyy-MM-dd")

                [void]$combinedNotes.AppendLine("## Version $version - $date")
                [void]$combinedNotes.AppendLine("")
                [void]$combinedNotes.AppendLine($notes)
                [void]$combinedNotes.AppendLine("")
            }
        }

        return $combinedNotes.ToString()
    }
    catch {
        Write-Log "Failed to get combined release notes: $_" -Level "ERROR"
        return "Failed to generate release notes."
    }
}