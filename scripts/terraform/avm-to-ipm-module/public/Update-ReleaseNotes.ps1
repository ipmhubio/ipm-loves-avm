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
        [Microsoft.Azure.Cosmos.Table.CloudTable]$table,

        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $true)]
        [string]$ModulePath,

        [Parameter(Mandatory = $false)]
        [string]$Version
    )

    try {
        Write-Log "Getting combined release notes for package '$PackageName' up to version '$Version'" -Level "INFO"

        # Query all versions for this package
        $query = [Microsoft.Azure.Cosmos.Table.TableQuery]::new()
        $filter = "PartitionKey eq '$PackageName'"
        $query.FilterString = $filter

        $results = $table.ExecuteQuery($query)
        Write-Log "Found $($results.Count) total versions for package '$PackageName'" -Level "DEBUG"

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
                $currentVersion = [Version]($_.Properties["Version"].StringValue.TrimStart('v'))
                $currentVersion -le $targetVersion
            }
            Write-Log "Filtered to $($results.Count) versions up to $Version" -Level "DEBUG"
        }

        # Sort by CreatedAt date in reverse order (newest first)
        $sortedResults = $results | Sort-Object { $_.Properties["CreatedAt"].DateTime } -Descending
        Write-Log "Sorted results by creation date (newest first)" -Level "DEBUG"

        # Combine release notes with newest first
        $combinedNotes = New-Object System.Text.StringBuilder

        [void]$combinedNotes.AppendLine("# Release History")
        [void]$combinedNotes.AppendLine("")

        foreach ($result in $sortedResults) {
            if ($result.Properties.ContainsKey("ReleaseNotes") -and
                $result.Properties.ContainsKey("Version") -and
                $result.Properties.ContainsKey("CreatedAt")) {

                $version = $result.Properties["Version"].StringValue
                $notes = $result.Properties["ReleaseNotes"].StringValue.Trim()
                $date = $result.Properties["CreatedAt"].DateTime.ToString("yyyy-MM-dd")

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
        Write-Log "Failed to get combined release notes: $_" -Level "ERROR"
        throw
    }
}