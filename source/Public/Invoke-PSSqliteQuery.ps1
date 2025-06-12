using namespace Microsoft.Data.Sqlite

function Invoke-PSSqliteQuery
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [SqliteConnection]
        $SqliteConnection,

        [Parameter(Mandatory = $true)]
        [string]
        $Query,

        [Parameter()]
        [System.Collections.IDictionary]
        # SQL query parameters to be used in the query
        $Parameters = @{},

        [Parameter()]
        [switch]
        $keepAlive
    )

    # Create a new SQLite connection
    begin
    {
        if ($SqliteConnection.State -ne 'Open')
        {
            try
            {
                $SqliteConnection.Open()
            }
            catch
            {
                Write-Error -Message "Failed to open SQLite connection: $_"
                return
            }
        }
    }

    process
    {
        try
        {
            # Create a command to execute the query
            $command = $SqliteConnection.CreateCommand()
            $command.CommandText = $Query

            if ($PSBoundParameters.ContainsKey('Parameters') -and $Parameters.Count -gt 0)
            {
                # Add parameters to the command if provided
                foreach ($key in $Parameters.Keys)
                {
                    $parameter = $command.CreateParameter()
                    $parameter.ParameterName = $key
                    $parameter.Value = $Parameters[$key]
                    $null = $command.Parameters.Add($parameter)
                }
            }

            # Execute the query and fill a DataTable with the results
            # $dataAdapter = New-Object System.Data.SQLite.SQLiteDataAdapter($command)
            $dataReader = $command.ExecuteReader()
            $dataTable = [System.Data.DataTable]::new()
            $dataTable.Load($dataReader)
            $dataReader.Dispose()
            $null = $dataReader.Close()

            return $dataTable
        }
        catch
        {
            # TODO: think about closing the connection here if an error occurs
            Write-Error -Message "An error occurred while executing the query: $_"
        }
        finally
        {
            # Ensure the connection is closed
            if ($connection.State -eq 'Open')
            {
                $connection.Close()
            }
        }
    }

    end
    {
        if (-not $keepAlive.IsPresent)
        {
            # Close the connection if it is not needed anymore
            $SqliteConnection.Close()
        }
    }
}
