# Import required modules
using namespace Microsoft.Azure.Cosmos.Table

function Initialize-AzureStorageTable
{
    [CmdletBinding()]
    [OutputType([Microsoft.Azure.Cosmos.Table.CloudTable])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$StorageAccountKey,

        [Parameter(Mandatory = $true)]
        [string]$TableName,

        [Parameter(Mandatory = $false)]
        [bool]$UseAzurite = $true
    )

    try
    {
        # Install required modules if not present
        if (-not (Get-Module -ListAvailable -Name AzTable))
        {
            Write-Log "Installing AzTable module..." -Level "INFO"
            Install-Module -Name AzTable -Force -AllowClobber -Scope CurrentUser
        }
        Import-Module AzTable

        if ($UseAzurite)
        {
            Write-Log "Using Azurite local storage emulator..." -Level "INFO"
            $connectionString = "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;TableEndpoint=http://127.0.0.1:10002/devstoreaccount1;"
        }
        else
        {
            # Create connection string for real Azure Storage
            $connectionString = "DefaultEndpointsProtocol=https;AccountName=$StorageAccountName;AccountKey=$StorageAccountKey;EndpointSuffix=core.windows.net"
        }

        # Create CloudTable directly
        $storageAccount = [CloudStorageAccount]::Parse($connectionString)
        $client = New-Object Microsoft.Azure.Cosmos.Table.CloudTableClient([Uri]$storageAccount.TableEndpoint, $storageAccount.Credentials)
        [Microsoft.Azure.Cosmos.Table.CloudTable]$table = $client.GetTableReference($TableName)
        $null = $table.CreateIfNotExists()

        Write-Log "Successfully initialized Azure Storage Table: $TableName" -Level "SUCCESS"
        return $table
    }
    catch
    {
        Write-Log "Failed to initialize Azure Storage Table: $_" -Level "ERROR"
        throw
    }
}