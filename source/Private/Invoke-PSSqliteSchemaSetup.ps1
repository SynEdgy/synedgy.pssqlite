function Invoke-PSSqliteSchemaSetup
{
    <#
    .SYNOPSIS
    Applies the generated schema, ordered setup SQL and version marker atomically.
    .DESCRIPTION
    Owns only connections and transactions it creates. Supplied transactions are
    never committed, rolled back or disposed by this function.
    .PARAMETER DatabaseConfig
    Validated database configuration.
    .PARAMETER SqliteConnection
    Optional caller-owned open connection.
    .PARAMETER SqliteTransaction
    Optional active transaction on the supplied connection.
    .EXAMPLE
    Invoke-PSSqliteSchemaSetup -DatabaseConfig $config
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory)]
        [SQLiteDBConfig]
        $DatabaseConfig,

        [Parameter()]
        [Microsoft.Data.Sqlite.SqliteConnection]
        $SqliteConnection,

        [Parameter()]
        [Microsoft.Data.Sqlite.SqliteTransaction]
        $SqliteTransaction
    )

    $schemaSql = $DatabaseConfig.GetDatabaseSDL()
    $ownsConnection = -not $SqliteConnection
    $ownsTransaction = -not $SqliteTransaction
    if ($SqliteTransaction -and
        (-not $SqliteConnection -or $SqliteTransaction.Connection -ne $SqliteConnection))
    {
        throw [ArgumentException]::new('SqliteTransaction must belong to the supplied SqliteConnection.')
    }

    try
    {
        if ($ownsConnection)
        {
            $SqliteConnection = New-PSSqliteConnection -ConnectionString $DatabaseConfig.ConnectionString
            $SqliteConnection.Open()
        }
        elseif ($SqliteConnection.State -ne 'Open')
        {
            throw [ArgumentException]::new('The supplied SqliteConnection must be open.')
        }

        if ($ownsTransaction) { $SqliteTransaction = $SqliteConnection.BeginTransaction() }

        $queryParameters = @{
            SqliteConnection = $SqliteConnection
            SqliteTransaction = $SqliteTransaction
            ErrorAction = 'Stop'
        }

        if (-not [string]::IsNullOrWhiteSpace($schemaSql))
        {
            $null = Invoke-PSSqliteQuery @queryParameters -CommandText $schemaSql
        }

        foreach ($statement in $DatabaseConfig.Schema.SetupSql)
        {
            Write-Verbose -Message ("Applying setup SQL '{0}'." -f $statement['Name'])
            $null = Invoke-PSSqliteQuery @queryParameters -CommandText $statement['Sql']
        }

        $null = Invoke-PSSqliteQuery @queryParameters -CommandText 'CREATE TABLE IF NOT EXISTS _metadata (key TEXT PRIMARY KEY, value TEXT);'
        $null = Invoke-PSSqliteQuery @queryParameters -CommandText "INSERT OR REPLACE INTO _metadata (key,value) VALUES ('version',@version)" -Parameters @{ version = $DatabaseConfig.Version }

        if ($ownsTransaction) { $SqliteTransaction.Commit() }
    }
    catch
    {
        if ($ownsTransaction -and $SqliteTransaction) { $SqliteTransaction.Rollback() }

        throw
    }
    finally
    {
        if ($ownsTransaction -and $SqliteTransaction) { $SqliteTransaction.Dispose() }

        if ($ownsConnection -and $SqliteConnection) { $SqliteConnection.Dispose() }
    }
}
