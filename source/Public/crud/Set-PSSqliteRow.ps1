using namespace System.Collections
using namespace System.Collections.Generic

function Set-PSSqliteRow
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [SQLiteDBConfig]
        $SqliteDBConfig,

        [Parameter(Mandatory = $true)]
        [string]
        $TableName,

        [Parameter(Mandatory = $true)]
        [IDictionary]
        $RowData,

        [Parameter()]
        [IDictionary]
        $ClauseData,

        [Parameter()]
        [Microsoft.Data.Sqlite.SqliteConnection]
        $SqliteConnection = (New-PSSqliteConnection -ConnectionString $SqliteDBConfig.ConnectionString),

        [Parameter()]
        [switch]
        $KeepAlive,

        [Parameter()]
        [ValidateSet('UPDATE', 'UPSERT')]
        [string]
        $OnConflict = 'UPDATE'
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
        $sqlParameters = [ordered]@{}
        foreach ($columnName in $rowData.Keys.Where{$_ -in $columnNames})
        {
            # if you want to set null, use DBNULL or use another function to handle null values
            # here we just ignore null values (because of the PS pipeline works)
            if ($null -ne $RowData[$columnName])
            {
                $sqlParameters[$columnName] = $RowData[$columnName]
            }
            else
            {
                Write-Warning "Column '$columnName' in row data is null. It will be ignored."
            }
        }

        [System.Text.StringBuilder]$sb = [System.Text.StringBuilder]::new()
        $null = $sb.Append(('UPDATE '))
        $null = $sb.Append($TableName)
        $null = $sb.AppendLine(' SET ')
        $null = $sb.AppendLine(($RowData.Keys.ForEach{ '{0} = @{0}' -f $_ } -join ', '))
        $null = $sb.AppendLine(' WHERE 1=1')

        foreach ($key in $ClauseData.Keys)
        {
            if ($key -in $columnNames)
            {
                $clauseKey = 'clause_{0}' -f $key
                # renaming the key to clauseKey to avoid conflicts with RowData keys
                if ($null -ne $ClauseData[$key])
                {
                    if ($ClauseData[$key] -match '\*')
                    {
                        # Handle string values with quotes
                        $null = $sb.AppendLine((' AND {0} LIKE @{1}' -f $key, $clauseKey))
                        $sqlParameters[$clauseKey] = $ClauseData[$key] -replace '\*', '%'
                    }
                    else
                    {
                        # Handle other values directly
                        $null = $sb.AppendLine((' AND {0} = @{1}' -f $key, $clauseKey))
                        $sqlParameters[$clauseKey] = $ClauseData[$key]
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

        Write-Verbose -Message ('Executing query: {0}' -f $sb.ToString())
        Invoke-PSSqliteQuery -SqliteConnection $SqliteConnection -CommandText $sb.ToString() -Parameters $sqlParameters -keepAlive
    }
}
