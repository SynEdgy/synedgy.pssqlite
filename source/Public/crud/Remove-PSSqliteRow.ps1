function Remove-PSSSqliteRow
{
    <#
    .SYNOPSIS
    Deletes rows from a SQLite database table based on specified criteria.

    .DESCRIPTION
    This function deletes rows from a specified SQLite database table based on the provided criteria (ClauseData).
    It constructs a SQL DELETE query dynamically, applying a WHERE clause based on the keys and values in the ClauseData dictionary.
    If a key in ClauseData matches a column name in the table, it will be used.

    .PARAMETER SqliteDBConfig
    A configuration object containing the SQLite database configuration specific to this module.
    This object should include the connection string and schema information for the database.

    .PARAMETER TableName
    The name of the table from which to delete rows.

    .PARAMETER ClauseData
    A dictionary containing the criteria for selecting rows to delete.
    Keys are column names and values are the values to match against those columns.
    If a value contains an asterisk (*), it will be treated as a wildcard for a LIKE query.
    If ClauseData does not contain any values, all rows in the table will be deleted.
    The keys can also include special suffixes like 'Before' or 'After' to indicate
    date or numeric comparisons. If a key ends with 'Before', it will delete rows where the column value is less than the specified value.
    If a key ends with 'After', it will delete rows where the column value is greater than the specified value.

    .PARAMETER CaseSensitive
    A switch parameter that, when specified, makes the query case-sensitive.
    By default, the query is case-insensitive (using COLLATE NOCASE by default).

    .PARAMETER SqliteConnection
    A SqliteConnection object used to connect to the SQLite database.
    If not provided, a new connection will be created using the connection string from the SqliteDBConfig.

    .PARAMETER KeepAlive
    A switch parameter that, if specified, will keep the database connection open after the command completes.
    This is useful for scenarios where multiple commands will be executed in succession,
    preventing the overhead of opening and closing the connection repeatedly.
    If this parameter is not specified, the connection will be closed after the command completes.

    .EXAMPLE
    Remove-PSSqliteRow -SqliteDBConfig $config -TableName 'Users' -ClauseData @{ Name = 'John*';}
    Deletes rows from the 'Users' table where the Name starts with 'John'.

    .NOTES
    This function is part of a module that provides CRUD operations for SQLite databases.
    #>
    [CmdletBinding()]
    [OutputType([void])]
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
        [switch]
        # A switch parameter that makes the query case-sensitive.
        # By default, the query is case-insensitive (using COLLATE NOCASE by default).
        $CaseSensitive,

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
        $null = $sb.AppendLine(('DELETE FROM {0}' -f $TableName))
        $null = $sb.AppendLine(' WHERE 1=1')
        if (-not $CaseSensitive)
        {
            $collation = ' COLLATE NOCASE'
        }
        else
        {
            $collation = ''
        }

        foreach ($key in $ClauseData.Keys)
        {
            if ($key -in $columnNames)
            {
                if ($null -ne $ClauseData[$key])
                {
                    if ($ClauseData[$key] -match '\*')
                    {
                        # Handle string values with quotes
                        $null = $sb.AppendLine((' AND {0}{1} LIKE @{0}' -f $key, $collation))
                        $sqlParameters[$key] = $ClauseData[$key] -replace '\*', '%'
                    }
                    else
                    {
                        # Handle other values directly
                        $null = $sb.AppendLine((' AND {0}{1} = @{0}' -f $key, $collation))
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
            elseif ($key -in @(
                [System.Management.Automation.PSCmdlet]::CommonParameters
                [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            ))
            {
                Write-Debug -Message "Column '$key' is not a valid column in table '$TableName'."
            }
            else
            {
                Write-Warning -Message "Column '$key' is not a valid column in table '$TableName'."
            }
        }

        Write-Verbose -Message ('Executing query: {0} with parameters {1}' -f $sb.ToString(),($sqlParameters | ConvertTo-JSON -Depth 3))
        Invoke-PSSqliteQuery -SqliteConnection $SqliteConnection -CommandText $sb.ToString() -Parameters $sqlParameters -As 'DataTable' -KeepAlive:$KeepAlive
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
