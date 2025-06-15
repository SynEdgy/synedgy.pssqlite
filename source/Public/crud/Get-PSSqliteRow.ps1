function Get-PSSqliteRow
{
    <#
    .SYNOPSIS
        Retrieves a specific row from a SQLite database table.

    .DESCRIPTION
        This function retrieves a row from a specified SQLite database table based on the provided primary key value.

    .PARAMETER SqliteConnection
        The SQLite connection object to use for querying the database.

    .PARAMETER TableName
        The name of the table from which to retrieve the row.

    .PARAMETER PrimaryKeyValue
        The value of the primary key for the row to retrieve.

    .EXAMPLE
        Get-PSSqliteRow -SqliteConnection $connection -TableName 'users' -PrimaryKeyValue 1
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [SQLiteDBConfig]
        $SqliteDBConfig,

        [Parameter(Mandatory = $true)]
        [string]
        $TableName,

        [Parameter()]
        [IDictionary]
        $ClauseData,

        [Parameter()]
        [Microsoft.Data.Sqlite.SqliteConnection]
        $SqliteConnection = (New-PSSqliteConnection -ConnectionString $SqliteDBConfig.ConnectionString),

        [Parameter()]
        [switch]
        $KeepAlive
    )

    begin
    {
        if (-not $SqliteConnection)
        {
            $SqliteConnection = New-PSSqliteConnection -ConnectionString $SqliteDBConfig.ConnectionString
        }

        $tableDefinition = $SqliteDBConfig.Schema.tables[0].Where{$_.Name -eq $TableName}[0]
        $columnNames = $tableDefinition.Columns.Name
    }

    process
    {
        $sqlParameters = @{}
        [System.Text.StringBuilder]$sb = [System.Text.StringBuilder]::new()
        $null = $sb.AppendLine(('SELECT * FROM {0}' -f $TableName))
        $null = $sb.AppendLine(' WHERE 1=1')
        foreach ($key in $ClauseData.Keys)
        {
            if ($key -in $columnNames)
            {
                if ($null -ne $ClauseData[$key])
                {
                    if ($ClauseData[$key] -match '\*')
                    {
                        # Handle string values with quotes
                        $null = $sb.AppendLine((' AND {0} LIKE @{0}' -f $key))
                        $sqlParameters[$key] = $ClauseData[$key] -replace '\*', '%'
                    }
                    else
                    {
                        # Handle other values directly
                        $null = $sb.AppendLine((' AND {0} = @{0}' -f $key))
                        $sqlParameters[$key] = $ClauseData[$key]
                    }
                }
            }
            elseif (($key -replace 'Before$','') -in $columnNames)
            {
                # Handle special case for 'Before' suffix
                # This is to handle cases like 'CreatedBefore' or 'UpdatedBefore'
                $actualKey = $key -replace 'Before$',''
                $null = $sb.AppendLine((' AND {0} < @{1}' -f $actualKey, $key))
                if ($null -ne $ClauseData[$key])
                {
                    $sqlParameters[$key] = $ClauseData[$key]
                }
            }
            elseif (($key -replace 'After$','') -in $columnNames)
            {
                # Handle special case for 'After' suffix
                # This is to handle cases like 'CreatedAfter' or 'UpdatedAfter'
                $actualKey = $key -replace 'After$',''
                $null = $sb.Append((' AND {0} > @{1}' -f $actualKey, $key))
                if ($null -ne $ClauseData[$key])
                {
                    $sqlParameters[$key] = $ClauseData[$key]
                }
            }
            else
            {
                Write-Warning -Message "Column '$key' is not a valid column in table '$TableName'."
            }
        }

        Write-Verbose -Message ('Executing query: {0} with parameters {1}' -f $sb.ToString(),($sqlParameters | ConvertTo-JSON -Depth 3))
        Invoke-PSSqliteQuery -SqliteConnection $SqliteConnection -CommandText $sb.ToString() -Parameters $sqlParameters -keepAlive
    }

    end
    {
        if (-not $KeepAlive)
        {
            try
            {
                $SqliteConnection.Close()
                [Microsoft.Data.Sqlite.SqliteConnection]::ClearPool($SqliteConnection)
                Write-Debug -Message 'Database connection closed.'
            }
            catch
            {
                Write-Warning -Message 'Failed to close the database connection.'
            }
        }
    }
}
