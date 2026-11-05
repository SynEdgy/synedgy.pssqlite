# Database creation and CRUD

Start with a validated [configuration](Configuration-and-validation). The examples
below use the `Cars` table from that guide.

## Initialising a file-backed database

```powershell
$config = Get-PSSqliteDBConfig -Path '.\config\Example.PSSqliteConfig.yml'
Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop
```

You can also pass `-Path` directly to `Initialize-PSSqliteDatabase`.

Initialisation creates a missing database, generates table/view/index SQL from the
configuration, applies ordered `Schema.SetupSql`, and writes the `version` entry
in `_metadata`. Generated schema, setup SQL and that marker are applied in one
transaction. A failure rolls back that schema application; a newly created file
can still remain on disk.

For an existing file-backed database, the default `INCREMENTAL` mode compares its
version with the expected version. Current/newer versions are not reapplied.
Older or differing versions can trigger application of the new configuration.
Use `-ErrorAction Stop` so metadata/query errors do not get mistaken for successful
deployment.

| Mode | Intended behaviour |
|---|---|
| `CREATE` | Create a missing database; do not upgrade an existing database. |
| `INCREMENTAL` (default) | Apply a newer/differing configuration without deleting the database file. |
| `OVERWRITE` | Recreate the file, with backup and compatible-data restoration by default. |

`-Force` selects `OVERWRITE`, even if the version is already current. It is not an
"apply harmless changes" switch.

**Initialisation is not automatic schema diffing.** `CREATE TABLE IF NOT EXISTS`
does not add columns or replace constraints on an existing table. Existing views
and indexes are likewise not replaced merely by editing their definitions.
See [Schema upgrades and recovery](Schema-upgrades-and-recovery).

## Constraints, indexes and defaults

Columns can combine `AllowNull`, `Unique`, `CheckExpression`, `DefaultValue`,
`Collation` and `References`. Table `Constraints` support composite primary keys,
foreign keys, checks and indexes. Table indexes are generated as separate SQL
statements; the legacy column `Indexed` flag is not a substitute for an explicit
index definition. Table `Options` support `Strict` and `WithoutRowId`.

String defaults are **SQL expressions**. Use `DefaultValue: "'unknown'"` for a text
literal, `DefaultValue: CURRENT_TIMESTAMP` for an expression, or a YAML number for
a numeric default. A null default means no default clause.

For foreign-key enforcement, configure each connection before starting a
transaction:

```powershell
$connection = New-PSSqliteConnection -ConnectionString $config.ConnectionString
$connection.Open()
$null = Invoke-PSSqliteQuery -SqliteConnection $connection -CommandText 'PRAGMA foreign_keys=ON;' -KeepAlive -ErrorAction Stop
```

Always dispose a connection you create when finished.

## CRUD commands

The commands use the loaded schema to resolve tables and columns and construct
parameterised SQL. Configuration identifiers are trusted; parameter binding
protects values, not arbitrary untrusted table names or SQL.

| Command | Operation |
|---|---|
| `New-PSSqliteRow` | Insert supplied `RowData` into a configured table. |
| `Get-PSSqliteRow` | Read a configured table or view with optional `ClauseData`. |
| `Set-PSSqliteRow` | Update supplied `RowData` in rows matching `ClauseData`. |
| `Remove-PSSqliteRow` | Delete rows matching `ClauseData`. |

```powershell
$database = @{ SqliteDBConfig = $config; TableName = 'Cars'; ErrorAction = 'Stop' }

$null = New-PSSqliteRow @database -RowData @{
    Make = 'Toyota'
    Model = 'Corolla'
    Colour = 'Yellow'
    Year = 2024
    CreatedOn = '2026-11-05T12:00:00Z'
}

Get-PSSqliteRow @database -ClauseData @{ Make = 'Toyota' }

Set-PSSqliteRow @database -RowData @{ Colour = 'Blue' } -ClauseData @{ Id = 1 }
Remove-PSSqliteRow @database -ClauseData @{ Id = 1 }
```

Read results default to `PSCustomObject`. Do not treat write-command output as a
stable affected-row count or generated identifier; query explicitly if you need
those values.

**An empty/effectively empty filter can update or delete every row.** Invalid filter
keys can be warned about and ignored, and null equality values are ignored.
Validate destructive-operation filters in your wrapper before calling Set/Remove.
These helpers are not guarded by `-WhatIf` or an implicit single-row restriction.

`RowData` null values are ignored rather than written as SQL NULL. Pass
`[DBNull]::Value` to explicitly clear a field. For inserts, omitted columns use
SQLite defaults or NULL as allowed by their constraints.

### Filtering

Filters combine with **AND**; they are not an OR-expression language.

```powershell
# Equality and wildcard matching.
Get-PSSqliteRow @database -ClauseData @{ Make = 'Toyota'; Colour = 'Yel*' }

# Exclusive numeric/date ranges: Year > 2020 AND Year < 2025.
Get-PSSqliteRow @database -ClauseData @{ YearAfter = 2020; YearBefore = 2025 }

# Equality without the default COLLATE NOCASE.
Get-PSSqliteRow @database -ClauseData @{ Make = 'Toyota' } -CaseSensitive
```

The same `ClauseData` pattern applies to updates and deletes. `Before` and `After`
are suffixes added to the actual column name and generate `<` and `>`, not inclusive
bounds. Supply non-null values for range filters.

`*` is translated to SQL `%`. SQL LIKE wildcard characters `%` and `_` are not
automatically escaped. `-CaseSensitive` removes the helper's `COLLATE NOCASE`;
it does not guarantee case-sensitive LIKE matching or override a column's own
collation. SQLite's default NOCASE behaviour is not full Unicode case folding.

Dates stored as TEXT compare lexically. Store them in a consistent UTC ISO-8601
format if lexical comparisons must reflect chronological order.

Use parameterised direct SQL for OR, NULL predicates, ordering, paging or more
complex filters:

```powershell
$connection = New-PSSqliteConnection -ConnectionString $config.ConnectionString
try
{
    Invoke-PSSqliteQuery -SqliteConnection $connection -CommandText @'
SELECT * FROM Cars
WHERE Colour IS NULL OR Year >= @minimumYear
ORDER BY Id
LIMIT @pageSize;
'@ -Parameters @{ minimumYear = 2020; pageSize = 50 } -As PSCustomObject -ErrorAction Stop
}
finally
{
    $connection.Dispose()
}
```

Direct query parameters accept `$null` as SQL NULL.

### Wrapper commands

A consumer can expose domain-specific read commands and forward bound filters:

```powershell
function Get-Car
{
    [CmdletBinding()]
    param(
        [string] $Make,
        [string] $Colour,
        [int] $YearAfter
    )

    Get-PSSqliteRow -SqliteDBConfig (Get-MyModuleConfig) -TableName Cars -ClauseData $PSBoundParameters -ErrorAction Stop
}
```

`Get-MyModuleConfig` is your application's configuration accessor, not a PSSqlite
command. For writes, separate values to change from criteria selecting rows.
Require a suitable key for destructive operations.

## Views and output formats

`Schema.Views` supports structured `Columns`, `From`, `Joins`, `Where`, `GroupBy`,
`Having` and `OrderBy`, or a raw `Sql` definition with declared output columns.
Use views as read models through `Get-PSSqliteRow`; CRUD writes remain table-based.
Do not combine raw SQL with structured query clauses.

Read/query output formats include `PSCustomObject`, `OrderedDictionary`,
`DataTable`, `DataSet` and `DataReader`. `DataReader` is a buffered
`DataTableReader`, **not a streaming SQLite reader**; dispose it after use.
Large queries can consume substantial memory.

## In-memory databases and caller-owned transactions

An in-memory database requires an open connection kept alive across operations.
An initializer-created connection is not a usable persistent in-memory store
after that connection closes.

```powershell
# $config was loaded from YAML containing ConnectionString: 'Data Source=:memory:;'
$connection = New-PSSqliteConnection -ConnectionString $config.ConnectionString
$connection.Open()
$transaction = $connection.BeginTransaction()

try
{
    $owned = @{
        SqliteConnection = $connection
        SqliteTransaction = $transaction
        ErrorAction = 'Stop'
    }

    Initialize-PSSqliteDatabase -DatabaseConfig $config @owned
    $null = New-PSSqliteRow -SqliteDBConfig $config @owned -TableName Cars -RowData @{
        Make = 'Toyota'
        Model = 'Corolla'
    }

    $transaction.Commit()
}
catch
{
    $transaction.Rollback()
    throw
}
finally
{
    $transaction.Dispose()
    $connection.Dispose()
}
```

A supplied transaction must belong to the supplied open connection. Initialisation
and query/CRUD helpers do not complete it or close its connection. Without a
supplied transaction, initialisation creates and completes its own transaction
but leaves a supplied connection open.

Caller-owned initialisation supports `CREATE` and `INCREMENTAL` only; overwrite,
force and backup options are rejected. The supplied connection's database takes
precedence over configured paths.

For query/CRUD calls without a transaction, use `-KeepAlive` when reusing a
connection, especially an in-memory connection. Dispose caller-created resources
when finished. Data export/import have their own transaction behaviour; they do
not accept the CRUD `SqliteTransaction` parameter.

## Trusted setup SQL

Use ordered, named `Schema.SetupSql` blocks for triggers, FTS5 or explicit upgrade
SQL. Generated schema is applied first, setup blocks next, and the version marker
last, inside the schema transaction.

```yaml
ConnectionString: 'Data Source=:memory:;'
Version: '1.0.0'
Schema:
  SetupSql:
    - Name: search
      Sql: |
        CREATE VIRTUAL TABLE IF NOT EXISTS search USING fts5(body);
```

Setup runs when a schema version is applied, not on every query or unchanged
initialisation. It runs again on recreation. Names must be unique ignoring case.
Do not include transaction-control statements, connection PRAGMAs or operations
that cannot participate in the transaction. SQL must be trusted application
configuration, not text supplied by an agent or external user.

Next: [Schema upgrades and recovery](Schema-upgrades-and-recovery).
