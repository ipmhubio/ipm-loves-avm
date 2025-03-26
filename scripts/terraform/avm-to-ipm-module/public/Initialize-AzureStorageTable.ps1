# Import required modules
using namespace Microsoft.Azure.Cosmos.Table

function Initialize-AzureStorageTable
{
    [CmdletBinding()]
    [OutputType([Microsoft.Azure.Cosmos.Table.CloudTable])]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'AccountKey')]
        [Parameter(Mandatory = $true, ParameterSetName = 'SasToken')]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true, ParameterSetName = 'AccountKey')]
        [string]$StorageAccountKey,

        [Parameter(Mandatory = $true, ParameterSetName = 'SasToken')]
        [string]$SasToken,

        [Parameter(Mandatory = $true)]
        [string]$TableName,

        [Parameter(Mandatory = $false)]
        [bool]$UseAzurite = $false
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
        elseif ($PSCmdlet.ParameterSetName -eq 'SasToken')
        {
            # Create connection string using SAS token
            # Make sure the SAS token doesn't start with '?' as it will be added in the connection string
            if ($SasToken.StartsWith('?'))
            {
                $SasToken = $SasToken.Substring(1)
            }
            $connectionString = "DefaultEndpointsProtocol=https;AccountName=$StorageAccountName;TableEndpoint=https://$StorageAccountName.table.core.windows.net/;SharedAccessSignature=$SasToken"
            Write-Log "Using SAS token authentication for storage account: $StorageAccountName" -Level "INFO"
        }
        else
        {
            # Create connection string using storage account key
            $connectionString = "DefaultEndpointsProtocol=https;AccountName=$StorageAccountName;AccountKey=$StorageAccountKey;EndpointSuffix=core.windows.net"
            Write-Log "Using account key authentication for storage account: $StorageAccountName" -Level "INFO"
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