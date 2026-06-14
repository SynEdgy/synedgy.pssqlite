# synedgy.PSSqlite

A SQLite module for PowerShell built on `Microsoft.Data.Sqlite`.

## What it is for

`synedgy.PSSqlite` is meant for modules and applications that want a simple embedded
database without adding a separate database server. The main workflow is:

1. Define your schema in a `*.PSSqliteConfig.yml` file.
1. Load that configuration into a `SqliteDBConfig`.
1. Initialize the database from the schema.
1. Use the CRUD helpers to read and write data without hand-writing SQL for every operation.

It is especially useful for local persistence, caching, and PowerShell Universal apps or
APIs that need a lightweight single-file database.

## Read more

- Blog post: [New SQLite module for PowerShell](https://synedgy.com/new-sqlite-module-for-powershell/)

## Core concepts

### 1. Configuration-driven schema

The module expects a YAML configuration that describes:

- where the database file should live
- the schema version
- the tables and columns to create

Example:

```yaml
DatabasePath: $repository
DatabaseFile: test.db
Version: 0.0.3
Schema:
  Tables:
    Cars:
      Columns:
        Id:
          Type: INTEGER
          PrimaryKey: true
          AllowNull: false
        Make:
          Type: TEXT
        Model:
          Type: TEXT
        Colour:
          Type: TEXT
        Year:
          Type: INTEGER
```

If your module follows the convention `config\<ModuleName>.PSSqliteConfig.yml`, you can
discover that file with `Get-PSSqliteDBConfigFile`.

### 2. Database initialization

Load the configuration and initialize the database from it:

```powershell
$configPath = Get-PSSqliteDBConfigFile
$dbConfig = Get-PSSqliteDBConfig -Path $configPath

Initialize-PSSqliteDatabase -DatabaseConfig $dbConfig
```

`Initialize-PSSqliteDatabase` creates the database, applies the schema, and maintains the
`_metadata` table used to track the deployed schema version.

### 3. CRUD helpers without raw SQL

The intended pattern is for your public commands to pass `$PSBoundParameters` into
`ClauseData` or `RowData`.

Example wrapper:

```powershell
function Get-Car
{
    [CmdletBinding()]
    param
    (
        [string] $Make,
        [string] $Model,
        [string] $Colour,
        [int] $Year
    )

    Get-PSSqliteRow -SqliteDBConfig (Get-MyModuleConfig) -TableName 'Cars' -ClauseData $PSBoundParameters
}
```

The CRUD commands are:

- `Get-PSSqliteRow`
- `New-PSSqliteRow`
- `Set-PSSqliteRow`
- `Remove-PSSqliteRow`

Common behaviors:

- matching is case-insensitive by default
- `*` in `ClauseData` is translated to a `LIKE` query
- keys ending in `Before` and `After` become range filters
- parameters are passed safely to SQLite instead of being string-concatenated into SQL

Examples:

```powershell
Get-PSSqliteRow -SqliteDBConfig $dbConfig -TableName 'Cars' -ClauseData @{ Colour = 'Yel*' }

New-PSSqliteRow -SqliteDBConfig $dbConfig -TableName 'Cars' -RowData @{
    Make = 'Toyota'
    Model = 'Corolla'
    Colour = 'Yellow'
    Year = 2024
}

Set-PSSqliteRow -SqliteDBConfig $dbConfig -TableName 'Cars' -RowData @{
    Colour = 'Blue'
} -ClauseData @{
    Id = 1
}

Remove-PSSqliteRow -SqliteDBConfig $dbConfig -TableName 'Cars' -ClauseData @{
    Colour = 'Blue'
}
```

### 4. Direct SQL when needed

The module does not force you to stay inside the CRUD helpers. For custom queries, use
`New-PSSqliteConnection` together with `Invoke-PSSqliteQuery`.

```powershell
$connection = New-PSSqliteConnection -ConnectionString $dbConfig.ConnectionString

try
{
    Invoke-PSSqliteQuery `
        -SqliteConnection $connection `
        -CommandText 'SELECT * FROM Cars WHERE Colour LIKE @colour' `
        -Parameters @{ colour = 'Yel%' }
}
finally
{
    $connection.Dispose()
}
```

## Typical module integration

A common pattern in a consuming module is:

1. keep the loaded `SqliteDBConfig` in a module-scoped variable
1. expose a small helper like `Get-MyModuleConfig`
1. initialize the database at startup or installation time
1. build user-facing commands that translate PowerShell parameters into `ClauseData` and `RowData`

This keeps most of your module logic in PowerShell objects and lets `synedgy.PSSqlite`
handle schema creation, persistence, and basic query generation.

## Notes

Thanks Julien Nury for some of the ideas.
