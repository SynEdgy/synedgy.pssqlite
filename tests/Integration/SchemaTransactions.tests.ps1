BeforeAll {
    Import-Module synedgy.PSSqlite -Force -ErrorAction Stop

    function New-SchemaTestConfig
    {
        param(
            [string]$SetupSql = '',
            [string]$Version = '1.0.0',
            [switch]$FileBacked
        )
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $null = New-Item -ItemType Directory -Path $root
        $definition = @{
            DatabasePath = $root
            DatabaseFile = 'schema.db'
            Version = $Version
            Schema = @{
                Tables = [ordered]@{
                    parents = @{
                        Columns = [ordered]@{
                            id = @{ Type = 'TEXT'; AllowNull = $false }

                            revision = @{ Type = 'INTEGER'; AllowNull = $false; DefaultValue = 1 }
                        }

                        Constraints = @(
                            @{ Type = 'PrimaryKey'; Name = 'pk_parents'; Columns = @('id', 'revision') }

                            @{ Type = 'Check'; Name = 'ck_revision'; CheckExpression = 'revision > 0' }

                            @{ Type = 'Index'; Name = 'parent_revision'; Columns = @('revision') }
                        )
                    }

                    children = @{
                        Columns = [ordered]@{
                            id = @{ Type = 'INTEGER'; PrimaryKey = $true; AllowNull = $false }

                            parent_id = @{ Type = 'TEXT'; AllowNull = $false }

                            parent_revision = @{ Type = 'INTEGER'; AllowNull = $false }

                            label = @{ Type = 'TEXT'; AllowNull = $false; Unique = $true; Collation = 'NOCASE'; DefaultValue = "'unknown'"; CheckExpression = 'length(label) > 0' }
                        }

                        Constraints = @(
                            @{ Type = 'ForeignKey'; Name = 'fk_parent'; Columns = @('parent_id', 'parent_revision'); ForeignTable = 'parents'; ForeignColumns = @('id', 'revision'); OnDelete = 'CASCADE' }
                        )
                    }

                    links = @{
                        Columns = @{
                            parent_id = @{ Type = 'INTEGER'; AllowNull = $false; References = 'children(id)' }

                            value = @{ Type = 'REAL'; DefaultValue = 0 }
                        }
                    }
                }
            }
        }

        if (-not $FileBacked) { $definition.ConnectionString = 'Data Source=:memory:;' }

        if ($SetupSql) { $definition.Schema.SetupSql = @(@{ Name = 'custom'; Sql = $SetupSql }) }

        $path = Join-Path $root 'Pester.PSSqliteConfig.yml'
        ConvertTo-Yaml -Data $definition | Set-Content -LiteralPath $path
        $config = synedgy.PSSqlite\Get-PSSqliteDBConfig -Path $path
        if ($FileBacked) { $config.ConnectionString += 'Pooling=False;' }

        $config
    }
}

Describe 'Configured constraints and atomic setup' {
    BeforeEach {
        $connection = synedgy.PSSqlite\New-PSSqliteConnection
        $connection.Open()
        $null = synedgy.PSSqlite\Invoke-PSSqliteQuery -SqliteConnection $connection -CommandText 'PRAGMA foreign_keys=ON;' -KeepAlive -ErrorAction Stop
    }

    AfterEach {
        $connection.Dispose()
    }

    It 'Should enforce composite keys checks foreign keys and combined column constraints' {
        $config = New-SchemaTestConfig
        synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -ErrorAction Stop
        $query = @{ SqliteConnection = $connection; KeepAlive = $true; ErrorAction = 'Stop' }

        $null = synedgy.PSSqlite\Invoke-PSSqliteQuery @query -CommandText "INSERT INTO parents(id) VALUES ('parent'); INSERT INTO children(parent_id,parent_revision) VALUES ('parent',1);"
        $row = synedgy.PSSqlite\Invoke-PSSqliteQuery @query -CommandText 'SELECT * FROM children' -As PSCustomObject
        $row.label | Should -Be 'unknown'
        { synedgy.PSSqlite\Invoke-PSSqliteQuery @query -CommandText "INSERT INTO parents(id) VALUES ('parent')" } | Should -Throw '*UNIQUE*'
        { synedgy.PSSqlite\Invoke-PSSqliteQuery @query -CommandText "INSERT INTO parents VALUES ('bad',0)" } | Should -Throw '*CHECK*'
        { synedgy.PSSqlite\Invoke-PSSqliteQuery @query -CommandText "INSERT INTO children(parent_id,parent_revision,label) VALUES ('missing',1,'different')" } | Should -Throw '*FOREIGN KEY*'
        { synedgy.PSSqlite\Invoke-PSSqliteQuery @query -CommandText "INSERT INTO children(parent_id,parent_revision,label) VALUES ('parent',1,'UNKNOWN')" } | Should -Throw '*UNIQUE*'
        { synedgy.PSSqlite\Invoke-PSSqliteQuery @query -CommandText "INSERT INTO children(parent_id,parent_revision,label) VALUES ('parent',1,NULL)" } | Should -Throw '*NOT NULL*'
        { synedgy.PSSqlite\Invoke-PSSqliteQuery @query -CommandText "INSERT INTO links(parent_id) VALUES (999)" } | Should -Throw '*FOREIGN KEY*'
        $indexes = @(synedgy.PSSqlite\Invoke-PSSqliteQuery @query -CommandText "PRAGMA index_list('parents')" -As PSCustomObject)
        $indexes.name | Should -Contain 'parent_revision'
        $null = synedgy.PSSqlite\Invoke-PSSqliteQuery @query -CommandText 'INSERT INTO links(parent_id) VALUES (1)'
        (synedgy.PSSqlite\Invoke-PSSqliteQuery @query -CommandText 'SELECT value FROM links' -As PSCustomObject).value | Should -Be 0
        $null = synedgy.PSSqlite\Invoke-PSSqliteQuery @query -CommandText "DELETE FROM links; DELETE FROM parents WHERE id='parent'"
        @(synedgy.PSSqlite\Invoke-PSSqliteQuery @query -CommandText 'SELECT * FROM children' -As PSCustomObject).Count | Should -Be 0
    }

    It 'Should run ordered setup SQL once per schema version and allow FTS queries' {
        $config = New-SchemaTestConfig
        $config.Schema.SetupSql = @(
            @{ Name = 'fts'; Sql = 'CREATE VIRTUAL TABLE memory_fts USING fts5(body);' }

            @{ Name = 'seed'; Sql = "INSERT INTO memory_fts VALUES ('deployment approval');" }
        )
        synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -ErrorAction Stop
        synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -ErrorAction Stop
        $rows = @(synedgy.PSSqlite\Invoke-PSSqliteQuery -SqliteConnection $connection -CommandText "SELECT body FROM memory_fts WHERE memory_fts MATCH 'deployment'" -As PSCustomObject -KeepAlive -ErrorAction Stop)
        $rows.Count | Should -Be 1
        $rows[0].body | Should -Be 'deployment approval'
        $config.Version = '1.1.0'
        $config.Schema.SetupSql = @(@{ Name = 'upgrade'; Sql = "INSERT INTO memory_fts VALUES ('review policy')" })
        synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -ErrorAction Stop
        (synedgy.PSSqlite\Get-PSSqliteDBMetadata -SqliteConnection $connection -KeepAlive).version | Should -Be '1.1.0'
    }

    It 'Should roll back failed setup and preserve the previous schema version and data' {
        $config = New-SchemaTestConfig -SetupSql 'CREATE TABLE setup_probe (id INTEGER); INVALID SQL;'
        { synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -ErrorAction Stop } | Should -Throw '*syntax error*'
        @(synedgy.PSSqlite\Invoke-PSSqliteQuery -SqliteConnection $connection -CommandText "SELECT name FROM sqlite_master WHERE type='table'" -As PSCustomObject -KeepAlive).Count | Should -Be 0
        $config.Schema.SetupSql = @()
        synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -ErrorAction Stop
        $config.Version = '2.0.0'
        $config.Schema.SetupSql = @(@{ Name = 'bad'; Sql = "INSERT INTO parents(id) VALUES ('rolled-back'); CREATE TABLE upgrade_probe(id INTEGER); INVALID SQL;" })
        { synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -ErrorAction Stop } | Should -Throw
        (synedgy.PSSqlite\Get-PSSqliteDBMetadata -SqliteConnection $connection -KeepAlive).version | Should -Be '1.0.0'
        @(synedgy.PSSqlite\Invoke-PSSqliteQuery -SqliteConnection $connection -CommandText 'SELECT * FROM parents' -As PSCustomObject -KeepAlive).Count | Should -Be 0
    }

    It 'Should leave caller-owned schema transactions open for rollback' {
        $config = New-SchemaTestConfig
        $transaction = $connection.BeginTransaction()
        try
        {
            synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -SqliteTransaction $transaction -ErrorAction Stop
            (synedgy.PSSqlite\Get-PSSqliteDBMetadata -SqliteConnection $connection -SqliteTransaction $transaction).version | Should -Be '1.0.0'
            $transaction.Connection | Should -Be $connection
            $transaction.Rollback()
        }
        finally { $transaction.Dispose() }

        @(synedgy.PSSqlite\Invoke-PSSqliteQuery -SqliteConnection $connection -CommandText "SELECT name FROM sqlite_master WHERE name='_metadata'" -As PSCustomObject -KeepAlive).Count | Should -Be 0
    }

    It 'Should compare integer schema versions consistently and commit supplied-connection setup' {
        $config = New-SchemaTestConfig -Version '1'
        synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -ErrorAction Stop
        $config.Version = '2'
        $config.Schema.SetupSql = @(@{ Name = 'integer-upgrade'; Sql = 'CREATE TABLE integer_probe(id INTEGER)' })
        synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -ErrorAction Stop
        (synedgy.PSSqlite\Compare-PSSqliteDBVersion -DatabaseConfig $config -SqliteConnection $connection).direction | Should -Be '=='
        $config.Version = '1'
        (synedgy.PSSqlite\Compare-PSSqliteDBVersion -DatabaseConfig $config -SqliteConnection $connection).direction | Should -Be '>'
        $connection.State | Should -Be 'Open'
    }

    It 'Should preserve caller ownership after setup failure and reject destructive options' {
        $config = New-SchemaTestConfig -SetupSql 'INVALID SQL;'
        $transaction = $connection.BeginTransaction()
        try
        {
            { synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -SqliteTransaction $transaction -ErrorAction Stop } | Should -Throw
            $transaction.Connection | Should -Be $connection
            { synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -SqliteTransaction $transaction -Force } | Should -Throw '*not supported*'
            $transaction.Rollback()
        }
        finally { $transaction.Dispose() }
    }

    It 'Should apply setup atomically on the existing file-backed initialisation path' {
        $config = New-SchemaTestConfig -FileBacked -SetupSql 'CREATE TABLE setup_probe(id INTEGER); INVALID SQL;'
        { synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop } | Should -Throw
        $fileConnection = synedgy.PSSqlite\New-PSSqliteConnection -ConnectionString $config.ConnectionString
        try
        {
            @(synedgy.PSSqlite\Invoke-PSSqliteQuery -SqliteConnection $fileConnection -CommandText "SELECT name FROM sqlite_master WHERE type='table'" -As PSCustomObject -KeepAlive).Count | Should -Be 0
            $config.Schema.SetupSql = @(@{ Name = 'good'; Sql = 'CREATE TABLE setup_probe(id INTEGER);' })
            synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop
            (synedgy.PSSqlite\Get-PSSqliteDBMetadata -SqliteConnection $fileConnection -KeepAlive).version | Should -Be '1.0.0'
        }
        finally { $fileConnection.Dispose() }
    }

    It 'Should reject malformed setup and constraints rather than silently ignoring them' {
        $config = New-SchemaTestConfig
        $config.Schema.SetupSql = @(@{ Name = 'same'; Sql = 'SELECT 1' }, @{ Name = 'same'; Sql = 'SELECT 2' })
        { $config.GetDatabaseSDL() } | Should -Throw '*unique*'
        $definition = @{ ConnectionString = 'Data Source=:memory:;'; Schema = @{ SetupSql = @(@{ Name = 'empty' }) } }

        { [synedgy.PSSqlite.SQLiteDBConfig]::new($definition) } | Should -Throw '*Name and Sql*'
        { [synedgy.PSSqlite.SqliteDBSchema]::new(@{ SetpuSql = @() }) } | Should -Throw '*Unknown schema*'
        $config = New-SchemaTestConfig
        $config.Schema.Tables[0].Constraints += [synedgy.PSSqlite.SqlitePrimaryKeyTableConstraint]::new(@{ Columns = @('missing') })
        { $config.GetDatabaseSDL() } | Should -Throw '*unknown column*'
    }

    It 'Should apply both strict and without-rowid table options' {
        $config = New-SchemaTestConfig
        $config.Schema.Tables[0].Options = @('Strict', 'WithoutRowId')
        synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -ErrorAction Stop
        $table = synedgy.PSSqlite\Invoke-PSSqliteQuery -SqliteConnection $connection -CommandText "SELECT sql FROM sqlite_master WHERE name='parents'" -As PSCustomObject -KeepAlive
        $table.sql | Should -Match 'STRICT, WITHOUT ROWID'
        { synedgy.PSSqlite\Invoke-PSSqliteQuery -SqliteConnection $connection -CommandText "INSERT INTO parents VALUES ('invalid','not-an-integer')" -KeepAlive -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Caller-owned query and CRUD transactions' {
    BeforeEach {
        $connection = synedgy.PSSqlite\New-PSSqliteConnection
        $connection.Open()
        $config = New-SchemaTestConfig
        synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -ErrorAction Stop
    }

    AfterEach { $connection.Dispose() }

    It 'Should pass every CRUD operation through the transaction without closing it' {
        $transaction = $connection.BeginTransaction()
        $parameters = @{ SqliteDBConfig = $config; SqliteConnection = $connection; SqliteTransaction = $transaction; ErrorAction = 'Stop' }

        try
        {
            $null = synedgy.PSSqlite\New-PSSqliteRow @parameters -TableName parents -RowData @{ id = 'first'; revision = 1 }

            $null = synedgy.PSSqlite\New-PSSqliteRow @parameters -TableName parents -RowData @{ id = 'second'; revision = 1 }

            synedgy.PSSqlite\Set-PSSqliteRow @parameters -TableName parents -RowData @{ revision = 2 } -ClauseData @{ id = 'first' }

            (synedgy.PSSqlite\Get-PSSqliteRow @parameters -TableName parents -ClauseData @{ id = 'first' }).revision | Should -Be 2
            synedgy.PSSqlite\Remove-PSSqliteRow @parameters -TableName parents -ClauseData @{ id = 'second' }

            @(synedgy.PSSqlite\Get-PSSqliteRow @parameters -TableName parents).Count | Should -Be 1
            $connection.State | Should -Be 'Open'
            $transaction.Rollback()
        }
        finally { $transaction.Dispose() }

        @(synedgy.PSSqlite\Get-PSSqliteRow -SqliteDBConfig $config -SqliteConnection $connection -TableName parents -KeepAlive).Count | Should -Be 0
    }

    It 'Should bind SQL nulls and surface failures without completing a caller transaction' {
        $transaction = $connection.BeginTransaction()
        try
        {
            $parameters = @{ SqliteConnection = $connection; SqliteTransaction = $transaction; ErrorAction = 'Stop' }

            (synedgy.PSSqlite\Invoke-PSSqliteQuery @parameters -CommandText 'SELECT @value IS NULL AS is_null' -Parameters @{ value = $null } -As PSCustomObject).is_null | Should -Be 1
            { synedgy.PSSqlite\Invoke-PSSqliteQuery @parameters -CommandText 'INVALID SQL' } | Should -Throw
            { synedgy.PSSqlite\New-PSSqliteRow -SqliteDBConfig $config @parameters -TableName parents -RowData @{ id = 'invalid'; revision = 0 } } | Should -Throw
            $transaction.Connection | Should -Be $connection
            $transaction.Rollback()
        }
        finally { $transaction.Dispose() }
    }

    It 'Should reject a transaction from another connection without closing either connection' {
        $otherConnection = synedgy.PSSqlite\New-PSSqliteConnection
        $otherConnection.Open()
        $transaction = $otherConnection.BeginTransaction()
        try
        {
            { synedgy.PSSqlite\Invoke-PSSqliteQuery -SqliteConnection $connection -SqliteTransaction $transaction -CommandText 'SELECT 1' } | Should -Throw '*supplied open*'
            { synedgy.PSSqlite\Initialize-PSSqliteDatabase -DatabaseConfig $config -SqliteConnection $connection -SqliteTransaction $transaction } | Should -Throw '*belong*'
            $connection.State | Should -Be 'Open'
            $otherConnection.State | Should -Be 'Open'
            $transaction.Rollback()
        }
        finally { $transaction.Dispose(); $otherConnection.Dispose() }
    }

    It 'Should return a usable buffered reader and release a non-kept connection' {
        $reader = synedgy.PSSqlite\Invoke-PSSqliteQuery -SqliteConnection $connection -CommandText 'SELECT 42 AS value' -As DataReader -ErrorAction Stop
        try
        {
            $reader.Read() | Should -BeTrue
            $reader.GetInt64(0) | Should -Be 42
        }
        finally { $reader.Dispose() }

        $connection.State | Should -Be 'Closed'
    }
}
