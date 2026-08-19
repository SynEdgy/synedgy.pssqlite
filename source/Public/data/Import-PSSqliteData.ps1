function Import-PSSqliteData
{
    <#
    .SYNOPSIS
    Imports a JSON data dump into the configured SQLite schema.

    .DESCRIPTION
    Restores rows from an Export-PSSqliteData dump by matching table and column
    names case-insensitively against the current schema. Tables and columns that no
    longer exist are skipped, while new columns use their SQLite defaults. Import
    order is derived from destination foreign keys so parent tables are restored
    before child tables. Cyclic constraints are deferred, and the transaction is
    rejected if SQLite reports foreign-key violations. Other import errors are
    reported per row so compatible rows can still be attempted.

    .PARAMETER SqliteDBConfig
    The destination database configuration containing the current schema.

    .PARAMETER Path
    The directory containing the dump manifest and per-table JSON files.

    .PARAMETER SqliteConnection
    An existing SQLite connection to use. When omitted, the command creates and
    disposes a connection from the configuration connection string.

    .EXAMPLE
    Import-PSSqliteData -SqliteDBConfig $config -Path '.\backup'

    Restores all compatible data from the backup directory.
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
        $SqliteConnection
    )

    $dumpPath = Get-PSSqliteAbsolutePath -Path $Path
    $manifestPath = Join-Path -Path $dumpPath -ChildPath '_manifest.json'
    $ownsConnection = -not $PSBoundParameters.ContainsKey('SqliteConnection')

    if (-not (Test-Path -Path $manifestPath -PathType Leaf))
    {
        throw [System.IO.FileNotFoundException]::new("SQLite data dump manifest not found: $manifestPath")
    }

    $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.Format -ne 'synedgy.PSSqlite.data' -or $manifest.FormatVersion -ne 1)
    {
        throw [System.IO.InvalidDataException]::new("Unsupported SQLite data dump format in '$manifestPath'.")
    }

    if (-not $SqliteConnection)
    {
        $SqliteConnection = New-PSSqliteConnection -ConnectionString $SqliteDBConfig.ConnectionString
    }

    $results = @()
    $transaction = $null
    $committed = $false

    try
    {
        if ($SqliteConnection.State -ne 'Open')
        {
            $SqliteConnection.Open()
        }

        $manifestTablesByName = @{}
        $tableDependencies = @{}

        foreach ($manifestTable in @($manifest.Tables))
        {
            $tableName = [string]$manifestTable.Name
            $manifestTablesByName[$tableName] = $manifestTable
            $tableDependencies[$tableName] = @()

            if (-not $SqliteDBConfig.Schema.GetTable($tableName))
            {
                continue
            }

            $quotedTableLiteral = $tableName.Replace("'", "''")
            $foreignKeys = @(Invoke-PSSqliteQuery -SqliteConnection $SqliteConnection -CommandText "PRAGMA foreign_key_list('$quotedTableLiteral');" -As PSCustomObject -KeepAlive -ErrorAction Stop)

            foreach ($foreignKey in $foreignKeys)
            {
                $parentTableName = [string]$foreignKey.table
                if (
                    $parentTableName -ine $tableName -and
                    $manifestTablesByName.ContainsKey($parentTableName)
                )
                {
                    $tableDependencies[$tableName] += $parentTableName
                }
            }
        }

        # Re-read dependencies after all manifest table names are known.
        foreach ($tableName in @($manifestTablesByName.Keys))
        {
            if (-not $SqliteDBConfig.Schema.GetTable($tableName))
            {
                continue
            }

            $quotedTableLiteral = $tableName.Replace("'", "''")
            $foreignKeys = @(Invoke-PSSqliteQuery -SqliteConnection $SqliteConnection -CommandText "PRAGMA foreign_key_list('$quotedTableLiteral');" -As PSCustomObject -KeepAlive -ErrorAction Stop)
            $tableDependencies[$tableName] = @(
                $foreignKeys |
                    ForEach-Object { [string]$_.table } |
                    Where-Object {
                        $_ -ine $tableName -and
                        $manifestTablesByName.ContainsKey($_)
                    } |
                    Select-Object -Unique
            )
        }

        $pendingTableNames = [System.Collections.ArrayList]::new()
        $null = $pendingTableNames.AddRange([object[]]@($manifestTablesByName.Keys))
        $orderedTableNames = @()

        while ($pendingTableNames.Count -gt 0)
        {
            $readyTableNames = @(
                $pendingTableNames |
                    Where-Object {
                        $tableName = [string]$_
                        @($tableDependencies[$tableName] | Where-Object { $_ -in $pendingTableNames }).Count -eq 0
                    } |
                    Sort-Object
            )

            if ($readyTableNames.Count -eq 0)
            {
                # Remaining tables form a dependency cycle. Deferred constraints
                # allow the cycle to be populated before integrity is checked.
                $orderedTableNames += @($pendingTableNames | Sort-Object)
                $pendingTableNames.Clear()
                break
            }

            foreach ($readyTableName in $readyTableNames)
            {
                $orderedTableNames += $readyTableName
                $null = $pendingTableNames.Remove($readyTableName)
            }
        }

        $transaction = $SqliteConnection.BeginTransaction()

        $deferCommand = $SqliteConnection.CreateCommand()
        try
        {
            $deferCommand.Transaction = $transaction
            $deferCommand.CommandText = 'PRAGMA defer_foreign_keys = ON;'
            $null = $deferCommand.ExecuteNonQuery()
        }
        finally
        {
            $deferCommand.Dispose()
        }

        foreach ($tableName in $orderedTableNames)
        {
            $manifestTable = $manifestTablesByName[$tableName]
            $tableDefinition = $SqliteDBConfig.Schema.GetTable([string]$manifestTable.Name)
            if (-not $tableDefinition)
            {
                $results += [PSCustomObject][ordered]@{
                    TableName = [string]$manifestTable.Name
                    Attempted = 0
                    Imported = 0
                    Failed = 0
                    Status = 'SkippedTable'
                    PSTypeName = 'synedgy.PSSqlite.DataImportTableResult'
                }
                continue
            }

            $tablePath = Join-Path -Path $dumpPath -ChildPath ([string]$manifestTable.File)
            if (-not (Test-Path -Path $tablePath -PathType Leaf))
            {
                throw [System.IO.FileNotFoundException]::new("SQLite table dump file not found: $tablePath")
            }

            $tableDump = Get-Content -Path $tablePath -Raw | ConvertFrom-Json
            if ($tableDump.FormatVersion -ne 1 -or $tableDump.TableName -ine $manifestTable.Name)
            {
                throw [System.IO.InvalidDataException]::new("Invalid SQLite table dump file: $tablePath")
            }

            $sourceColumns = @($tableDump.Columns)
            $targetColumns = @($tableDefinition.Columns.Name)
            $compatibleColumns = @($targetColumns | Where-Object { $_ -in $sourceColumns })
            $attempted = 0
            $imported = 0
            $failed = 0

            if ($compatibleColumns.Count -eq 0)
            {
                $results += [PSCustomObject][ordered]@{
                    TableName = $tableDefinition.Name
                    Attempted = 0
                    Imported = 0
                    Failed = 0
                    Status = 'SkippedColumns'
                    PSTypeName = 'synedgy.PSSqlite.DataImportTableResult'
                }
                continue
            }

            $quotedTableName = '"{0}"' -f $tableDefinition.Name.Replace('"', '""')
            $quotedColumnNames = @($compatibleColumns | ForEach-Object { '"{0}"' -f $_.Replace('"', '""') })
            $parameterNames = @(for ($parameterIndex = 0; $parameterIndex -lt $compatibleColumns.Count; $parameterIndex++) { "@p$parameterIndex" })
            $commandText = 'INSERT INTO {0} ({1}) VALUES ({2});' -f $quotedTableName, ($quotedColumnNames -join ', '), ($parameterNames -join ', ')

            foreach ($row in @($tableDump.Rows))
            {
                $attempted++
                $command = $SqliteConnection.CreateCommand()
                $command.Transaction = $transaction
                $command.CommandText = $commandText

                try
                {
                    for ($parameterIndex = 0; $parameterIndex -lt $compatibleColumns.Count; $parameterIndex++)
                    {
                        $columnName = $compatibleColumns[$parameterIndex]
                        $sourceProperty = $row.PSObject.Properties |
                            Where-Object Name -IEQ $columnName |
                            Select-Object -First 1
                        $value = $null

                        if ($sourceProperty)
                        {
                            $value = $sourceProperty.Value
                        }

                        if (
                            $null -ne $value -and
                            $value.PSObject.Properties['PSSqliteType'] -and
                            $value.PSSqliteType -eq 'Blob'
                        )
                        {
                            $value = [Convert]::FromBase64String([string]$value.Value)
                        }

                        $parameter = $command.CreateParameter()
                        $parameter.ParameterName = "@p$parameterIndex"
                        if ($null -eq $value)
                        {
                            $parameter.Value = [DBNull]::Value
                        }
                        else
                        {
                            $parameter.Value = $value
                        }

                        $null = $command.Parameters.Add($parameter)
                    }

                    $null = $command.ExecuteNonQuery()
                    $imported++
                }
                catch
                {
                    $failed++
                    Write-Error -Message ("Failed to import row {0} into table '{1}': {2}" -f $attempted, $tableDefinition.Name, $_.Exception.Message)
                }
                finally
                {
                    $command.Dispose()
                }
            }

            $results += [PSCustomObject][ordered]@{
                TableName = $tableDefinition.Name
                Attempted = $attempted
                Imported = $imported
                Failed = $failed
                Status = if ($failed -eq 0) { 'Imported' } else { 'PartiallyImported' }
                PSTypeName = 'synedgy.PSSqlite.DataImportTableResult'
            }
        }

        $foreignKeyCheckCommand = $SqliteConnection.CreateCommand()
        try
        {
            $foreignKeyCheckCommand.Transaction = $transaction
            $foreignKeyCheckCommand.CommandText = 'PRAGMA foreign_key_check;'
            $foreignKeyReader = $foreignKeyCheckCommand.ExecuteReader()
            $foreignKeyViolations = @()

            try
            {
                while ($foreignKeyReader.Read())
                {
                    $foreignKeyViolations += [PSCustomObject]@{
                        TableName = [string]$foreignKeyReader.GetValue(0)
                        RowId = $foreignKeyReader.GetValue(1)
                        ParentTable = [string]$foreignKeyReader.GetValue(2)
                        ForeignKeyId = $foreignKeyReader.GetValue(3)
                    }
                }
            }
            finally
            {
                $foreignKeyReader.Dispose()
            }

            if ($foreignKeyViolations.Count -gt 0)
            {
                $firstViolation = $foreignKeyViolations[0]
                throw [System.Data.DataException]::new(
                    "The imported data contains $($foreignKeyViolations.Count) foreign-key violation(s). First violation: table '$($firstViolation.TableName)', row '$($firstViolation.RowId)', parent table '$($firstViolation.ParentTable)'."
                )
            }
        }
        finally
        {
            $foreignKeyCheckCommand.Dispose()
        }

        $transaction.Commit()
        $committed = $true
    }
    finally
    {
        if ($transaction)
        {
            if (-not $committed)
            {
                $transaction.Rollback()
            }

            $transaction.Dispose()
        }

        if ($ownsConnection -and $SqliteConnection)
        {
            $SqliteConnection.Close()
            [Microsoft.Data.Sqlite.SqliteConnection]::ClearPool($SqliteConnection)
            $SqliteConnection.Dispose()
        }
    }

    return $results
}
