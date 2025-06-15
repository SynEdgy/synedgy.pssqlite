using namespace Microsoft.Data.Sqlite
using namespace System.Collections.Specialized

function Invoke-PSSqliteQuery
{
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
        [switch]
        $keepAlive
    )

    process
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

        try
        {
            # Create a command to execute the query
            $command = $SqliteConnection.CreateCommand()
            $command.CommandText = $CommandText
            $command.CommandTimeout = $CommandTimeout

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

            # Execute the query and load a DataTable with the results
            $dataReader = $command.ExecuteReader()
            $dataTable = [System.Data.DataTable]::new()
            $null = $dataTable.Load($dataReader)
            $null = $dataReader.Dispose()
            $null = $dataReader.Close()
        }
        catch
        {
            Write-Error -Message "An error occurred while executing the query: $_"
        }
        finally
        {
            # Ensure the connection is closed
            if ($SqliteConnection.State -eq 'Open' -and -not $keepAlive.IsPresent)
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
                # Return the data reader directly
                $dataReader
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
