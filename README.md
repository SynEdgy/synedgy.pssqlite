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

## Getting started

This example keeps everything in memory and shows the full flow: YAML config, tables,
a view, initialization, and CRUD.

```powershell
$yaml = @'
ConnectionString: Data Source=:memory:
Version: 1.0.0
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
  Views:
    CarSummary:
      Columns:
        CarId:
          Source:
            Table: Cars
            Column: Id
        Description:
          Expression: Cars.Make || ' ' || Cars.Model
        Colour:
          Source:
            Table: Cars
            Column: Colour
      From:
        Table: Cars
'@

$dbConfig = Get-PSSqliteDBConfig -Definition ($yaml | ConvertFrom-Yaml -Ordered)
$connection = New-PSSqliteConnection -ConnectionString $dbConfig.ConnectionString

try
{
    Initialize-PSSqliteDatabase -DatabaseConfig $dbConfig

    New-PSSqliteRow -SqliteDBConfig $dbConfig -SqliteConnection $connection -KeepAlive -TableName 'Cars' -RowData @{
        Make = 'Toyota'
        Model = 'Corolla'
        Colour = 'Yellow'
        Year = 2024
    }

    New-PSSqliteRow -SqliteDBConfig $dbConfig -SqliteConnection $connection -KeepAlive -TableName 'Cars' -RowData @{
        Make = 'Ford'
        Model = 'Focus'
        Colour = 'Blue'
        Year = 2020
    }

    Get-PSSqliteRow -SqliteDBConfig $dbConfig -SqliteConnection $connection -KeepAlive -TableName 'Cars'
    Get-PSSqliteRow -SqliteDBConfig $dbConfig -SqliteConnection $connection -KeepAlive -TableName 'Cars' -ClauseData @{ Colour = 'Yel*' }
    Get-PSSqliteRow -SqliteDBConfig $dbConfig -SqliteConnection $connection -KeepAlive -TableName 'CarSummary'

    Set-PSSqliteRow -SqliteDBConfig $dbConfig -SqliteConnection $connection -KeepAlive -TableName 'Cars' -RowData @{
        Colour = 'Red'
    } -ClauseData @{
        Make = 'Toyota'
        Model = 'Corolla'
    }

    Remove-PSSqliteRow -SqliteDBConfig $dbConfig -SqliteConnection $connection -KeepAlive -TableName 'Cars' -ClauseData @{
        Make = 'Ford'
    }

    Get-PSSqliteRow -SqliteDBConfig $dbConfig -SqliteConnection $connection -KeepAlive -TableName 'CarSummary'
}
finally
{
    $connection.Dispose()
}
```

## Core concepts

### 1. Configuration-driven schema

The module expects a YAML configuration that describes:

- where the database file should live
- the schema version
- the tables and columns to create
- optional views to expose read models

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
  Views:
    CarSummary:
      Columns:
        CarId:
          Source:
            Table: c
            Column: Id
        Make:
          Source:
            Table: c
            Column: Make
      From:
        Table: Cars
        Alias: c
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

Views can use either:

- a structured YAML definition with `Columns`, `From`, `Joins`, `Where`, `GroupBy`, `Having`, and `OrderBy`
- a raw `Sql:` block for advanced SQLite view definitions while still declaring output columns for `Get-PSSqliteRow`

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

`Get-PSSqliteRow` can target either a table or a configured view. The write helpers stay
table-oriented.

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
