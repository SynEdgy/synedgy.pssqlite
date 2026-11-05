using namespace Microsoft.Data.Sqlite
using namespace System.Collections.Specialized

function Invoke-PSSqliteQuery
{
    <#
    .SYNOPSIS
    Executes a SQL query against a SQLite database and returns the results in the specified format.

    .DESCRIPTION
    This function provides a way to execute SQL queries against a SQLite database and retrieve the results in various formats.

    .PARAMETER SqliteConnection
    A SqliteConnection object used to connect to the SQLite database.

    .PARAMETER CommandText
    The SQL query to execute.
    This can be a simple SELECT statement or any valid SQL command.

    .PARAMETER As
    The format in which to return the results. Possible values are 'DataTable', 'DataReader', 'DataSet', 'OrderedDictionary', and 'PSCustomObject'.
    DataReader returns a buffered reader that the caller must dispose.

    .PARAMETER CastAs
    An optional type to cast the results to.

    .PARAMETER Parameters
    A hashtable of parameters to include in the query.

    .PARAMETER CommandTimeout
    The timeout period for the command, in seconds.

    .PARAMETER SqliteTransaction
    Caller-owned transaction on SqliteConnection. The connection stays open, and
    the caller is responsible for committing, rolling back and disposing it.

    .PARAMETER keepAlive
    A switch parameter that, if specified, will keep the database connection open after the command completes.
    This is useful for scenarios where multiple commands will be executed in succession,
    preventing the overhead of opening and closing the connection repeatedly.
    If this parameter is not specified, the connection will be closed after the command completes.

    .EXAMPLE
    Invoke-PSSqliteQuery -SqliteConnection $connection -CommandText "SELECT * FROM Users" -As DataTable

    .NOTES
    This function is part of a module that provides CRUD operations for SQLite databases.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [SqliteConnection]
        $SqliteConnection,

        [Parameter(Mandatory = $true)]
        [Alias('Query')]
        [string]
        $CommandText,

        [Parameter()]
        [ValidateSet('DataTable', 'DataReader', 'DataSet','OrderedDictionary','PSCustomObject')]
        [string]
        # Specifies the type of output to return. Default is 'DataTable'.
        $As = 'DataTable',

        [Parameter()]
        [Type]
        $CastAs,

        [Parameter()]
        [System.Collections.IDictionary]
        # SQL query parameters to be used in the query
        $Parameters = @{},

        [Parameter()]
        [int]
        # Command timeout in seconds
        $CommandTimeout = 30,

        [Parameter()]
        [SqliteTransaction]
        $SqliteTransaction,

        [Parameter()]
        [switch]
        $keepAlive
    )

    process
    {
        if ($SqliteTransaction -and
            ($SqliteConnection.State -ne 'Open' -or $SqliteTransaction.Connection -ne $SqliteConnection))
        {
            throw [System.ArgumentException]::new('SqliteTransaction must be active on the supplied open SqliteConnection.')
        }

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

        $command = $null
        $dataReader = $null
        try
        {
            # Create a command to execute the query
            $command = $SqliteConnection.CreateCommand()
            $command.CommandText = $CommandText
            $command.CommandTimeout = $CommandTimeout
            if ($SqliteTransaction) { $command.Transaction = $SqliteTransaction }

            if ($PSBoundParameters.ContainsKey('Parameters') -and $Parameters.Count -gt 0)
            {
                # Add parameters to the command if provided
                foreach ($key in $Parameters.Keys)
                {
                    $parameter = $command.CreateParameter()
                    $parameter.ParameterName = $key
                    $parameter.Value = if ($null -eq $Parameters[$key]) { [DBNull]::Value } else { $Parameters[$key] }

                    $null = $command.Parameters.Add($parameter)
                }
            }

            # Execute the query and load a DataTable with the results
            $dataReader = $command.ExecuteReader()
            $dataTable = [System.Data.DataTable]::new()
            $null = $dataTable.Load($dataReader)
        }
        catch
        {
            Write-Error -Message "An error occurred while executing the query: $_"
            return
        }
        finally
        {
            if ($dataReader) { $dataReader.Dispose() }

            if ($command) { $command.Dispose() }

            if ($SqliteConnection.State -eq 'Open' -and -not $keepAlive.IsPresent -and
                -not $SqliteTransaction)
            {
                Write-Debug -Message "Closing SQLite connection & clearing pool."
                $null = $SqliteConnection.Close()
                [Microsoft.Data.Sqlite.SqliteConnection]::ClearPool($SqliteConnection)
            }
        }

        # Processing output
        $transformedResult = switch ($As)
        {
            'DataTable'
            {
                $dataTable
            }

            'DataReader'
            {
                # Like the other formats, results are buffered before releasing SQL resources.
                ,$dataTable.CreateDataReader()
            }

            'OrderedDictionary'
            {
                # Convert DataTable to OrderedDictionary
                foreach ($row in $dataTable.Rows)
                {
                    $rowDict = [System.Collections.Specialized.OrderedDictionary]::new()
                    foreach ($col in $dataTable.Columns)
                    {
                        $rowDict[$col.ColumnName] = $null
                        if ($row[$col] -isnot [System.DBNull])
                        {
                            $rowDict[$col.ColumnName] = $row[$col.ColumnName]
                        }
                    }

                    $rowDict
                }
            }

            'PSCustomObject'
            {
                # Convert DataTable to OrderedDictionary
                foreach ($row in $dataTable.Rows)
                {
                    $rowObj = [PSCustomObject]@{}

                    foreach ($col in $dataTable.Columns)
                    {
                        if ($row[$col] -isnot [System.DBNull])
                        {
                            $null = $rowObj.PSObject.Properties.Add([PSNoteProperty]::new($col.ColumnName, $row[$col]))
                        }
                        else
                        {
                            $null = $rowObj.PSObject.Properties.Add([PSNoteProperty]::new($col.ColumnName, $null))
                        }
                    }

                    # Add PSTypeName to the object, based on DatabaseName.TableName
                    if ($c.Database)
                    {
                        $null = $rowObj.PSObject.TypeNames.Insert(0,('{0}' -f $dataTable.TableName))
                        $null = $rowObj.PSObject.TypeNames.Insert(0,('{0}.{1}' -f $c.database, $dataTable.TableName))
                    }
                    elseif ($dataTable.TableName)
                    {
                        $null = $rowObj.PSObject.TypeNames.Insert(0,$dataTable.TableName)
                    }

                    $rowObj
                }
            }

            'DataSet'
            {
                # Create a DataSet and add the DataTable to it
                $dataSet = [System.Data.DataSet]::new()
                $null = $dataSet.Tables.Add($dataTable)
                $dataSet
            }

            default
            {
                Write-Warning -Message "Unsupported output type: $As. Returning DataTable instead."
                $dataTable
            }
        }

        if (-not $PSBoundParameters.ContainsKey('CastAs'))
        {
            if ($As -eq 'DataReader') { return ,$transformedResult }

            $transformedResult
        }
        elseif ($PSBoundParameters.ContainsKey('CastAs') -and $CastAs -ne $null)
        {
            # Cast the result to the specified type if provided
            try
            {
                $transformedResult -as $CastAs
            }
            catch
            {
                Write-Error -Message "Failed to cast result to type $CastAs : $_"
            }
        }
    }
}
