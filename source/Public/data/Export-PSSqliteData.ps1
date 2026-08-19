function Export-PSSqliteData
{
    <#
    .SYNOPSIS
    Exports configured SQLite table data to a portable JSON dump.

    .DESCRIPTION
    Exports every user table found in the SQLite database to a separate JSON file
    and writes a manifest describing the dump. Views, SQLite internal tables, and
    the module metadata table are not exported. SQLite BLOB values are Base64
    encoded so they can be restored without data loss.

    .PARAMETER SqliteDBConfig
    The database configuration that identifies the database to export.

    .PARAMETER Path
    The directory where the manifest and per-table JSON data files will be written.

    .PARAMETER SqliteConnection
    An existing SQLite connection to use. When omitted, the command creates and
    disposes a connection from the configuration connection string.

    .PARAMETER Force
    Overwrites an existing dump manifest and table files in the destination directory.

    .EXAMPLE
    Export-PSSqliteData -SqliteDBConfig $config -Path '.\backup' -Force

    Exports all user tables to the backup directory.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [SQLiteDBConfig]
        $SqliteDBConfig,

        [Parameter(Mandatory = $true)]
        [string]
        $Path,

        [Parameter()]
        [Microsoft.Data.Sqlite.SqliteConnection]
        $SqliteConnection,

        [Parameter()]
        [switch]
        $Force
    )

    $dumpPath = Get-PSSqliteAbsolutePath -Path $Path
    $manifestPath = Join-Path -Path $dumpPath -ChildPath '_manifest.json'
    $ownsConnection = -not $PSBoundParameters.ContainsKey('SqliteConnection')

    if ((Test-Path -Path $manifestPath -PathType Leaf) -and -not $Force)
    {
        throw [System.IO.IOException]::new("A SQLite data dump already exists at '$dumpPath'. Use Force to overwrite it.")
    }

    if (-not (Test-Path -Path $dumpPath -PathType Container))
    {
        $null = New-Item -Path $dumpPath -ItemType Directory -Force
    }

    if (-not $SqliteConnection)
    {
        $SqliteConnection = New-PSSqliteConnection -ConnectionString $SqliteDBConfig.ConnectionString
    }

    $manifestTables = @()
    $dumpTimestamp = Get-Date -Format 'yyyy-MM-dd_HH.mm.ss'

    try
    {
        if ($SqliteConnection.State -ne 'Open')
        {
            $SqliteConnection.Open()
        }

        $databaseTables = @(Invoke-PSSqliteQuery -SqliteConnection $SqliteConnection -CommandText @'
SELECT name
FROM sqlite_master
WHERE type = 'table'
  AND name NOT LIKE 'sqlite_%'
  AND name <> '_metadata'
ORDER BY name;
'@ -As PSCustomObject -KeepAlive -ErrorAction Stop)

        for ($tableIndex = 0; $tableIndex -lt $databaseTables.Count; $tableIndex++)
        {
            $tableName = [string]$databaseTables[$tableIndex].name
            $quotedTableName = '"{0}"' -f $tableName.Replace('"', '""')
            $quotedTableLiteral = $tableName.Replace("'", "''")
            $tableColumns = @(Invoke-PSSqliteQuery -SqliteConnection $SqliteConnection -CommandText "PRAGMA table_info('$quotedTableLiteral');" -As PSCustomObject -KeepAlive -ErrorAction Stop)
            $rows = @(Invoke-PSSqliteQuery -SqliteConnection $SqliteConnection -CommandText "SELECT * FROM $quotedTableName;" -As OrderedDictionary -KeepAlive -ErrorAction Stop)
            $serializedRows = @()

            foreach ($row in $rows)
            {
                $serializedRow = [ordered]@{}

                foreach ($columnName in $row.Keys)
                {
                    $value = $row[$columnName]
                    if ($value -is [byte[]])
                    {
                        $serializedRow[$columnName] = [ordered]@{
                            PSSqliteType = 'Blob'
                            Value = [Convert]::ToBase64String($value)
                        }
                    }
                    else
                    {
                        $serializedRow[$columnName] = $value
                    }
                }

                $serializedRows += [PSCustomObject]$serializedRow
            }

            $safeTableName = $tableName -replace '[^A-Za-z0-9_.-]', '_'
            $tableFileName = '{0:D4}-{1}_{2}.json' -f ($tableIndex + 1), $safeTableName, $dumpTimestamp
            $tablePath = Join-Path -Path $dumpPath -ChildPath $tableFileName
            $tableDump = [ordered]@{
                FormatVersion = 1
                TableName = $tableName
                Columns = @($tableColumns.name)
                Rows = @($serializedRows)
            }

            $tableDump |
                ConvertTo-Json -Depth 10 |
                Set-Content -Path $tablePath -Encoding UTF8 -Force

            $manifestTables += [PSCustomObject][ordered]@{
                Name = $tableName
                File = $tableFileName
                RowCount = $rows.Count
            }
        }

        $manifest = [ordered]@{
            Format = 'synedgy.PSSqlite.data'
            FormatVersion = 1
            CreatedAtUtc = [DateTime]::UtcNow.ToString('o')
            DatabaseVersion = $SqliteDBConfig.Version
            Tables = @($manifestTables)
        }

        $manifest |
            ConvertTo-Json -Depth 10 |
            Set-Content -Path $manifestPath -Encoding UTF8 -Force

        return [PSCustomObject][ordered]@{
            Path = $dumpPath
            ManifestPath = $manifestPath
            TableCount = $manifestTables.Count
            RowCount = [int](($manifestTables | Measure-Object -Property RowCount -Sum).Sum)
            PSTypeName = 'synedgy.PSSqlite.DataExportResult'
        }
    }
    finally
    {
        if ($ownsConnection -and $SqliteConnection)
        {
            $SqliteConnection.Close()
            [Microsoft.Data.Sqlite.SqliteConnection]::ClearPool($SqliteConnection)
            $SqliteConnection.Dispose()
        }
    }
}
