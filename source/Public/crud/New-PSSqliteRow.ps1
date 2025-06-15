using namespace System.Collections
using namespace System.Collections.Generic

function New-PSSqliteRow
{
    [CmdletBinding()]
    [OutputType([Int64])]
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

        $tableDefinition = $SqliteDBConfig.Schema.tables[0].Where{$_.Name -eq 'users'}[0]
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
        $null = $sb.AppendLine(('INSERT INTO {0} ({1})' -f $TableName, ($sqlParameters.Keys -join ', ')))
        $null = $sb.Append(' VALUES ({0})' -f ($sqlParameters.Keys.ForEach{ '@{0}' -f $_ } -join ', '))
        $null = $sb.AppendLine(' RETURNING *;')
        Write-Debug -Message ('Executing SQL: {0}' -f $sb.ToString())
        try
        {
            $returnedValue = Invoke-PSSqliteQuery -SqliteConnection $SqliteConnection -CommandText $sb.ToString() -Parameters $sqlParameters -KeepAlive -ErrorAction Stop
            Write-Verbose -Message ('Row inserted into table {0} successfully.' -f $TableName)
            $returnedValue
        }
        catch
        {
            Write-Error "Failed to insert row into table '$TableName': $_"
            return $null
        }
    }

    end
    {
        if ($SqliteConnection -and $KeepAlive -eq $false)
        {
            try
            {
                [Microsoft.Data.Sqlite.SqliteConnection]::ClearPool($SqliteConnection)
                $SqliteConnection.Close()
                Write-Verbose -Message 'Database connection closed.'
            }
            catch
            {
                Write-Warning -Message 'Failed to close the database connection.'
            }
        }
    }
}
