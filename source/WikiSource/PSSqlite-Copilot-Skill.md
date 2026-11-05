# PSSqlite Copilot Skill

This page documents a reusable Copilot skill for repositories that want to use
`synedgy.PSSqlite`.

Read [Configuration and validation](Configuration-and-validation),
[Database creation and CRUD](Database-creation-and-CRUD), and
[Schema upgrades and recovery](Schema-upgrades-and-recovery) for the full
configuration contract and operational caveats.

## Goal

Use this skill in a consuming repository when you want Copilot to:

- define or update a `*.PSSqliteConfig.yml` schema
- initialise a SQLite database from YAML
- create wrapper functions that pass `$PSBoundParameters` into `ClauseData` or `RowData`
- use `Get-PSSqliteRow`, `New-PSSqliteRow`, `Set-PSSqliteRow`, and `Remove-PSSqliteRow`
- define read models with `Schema.Views`
- preserve and restore data when recreating a database schema

## Recommended repository layout

In the consuming repository, add:

```text
.github/
  skills/
    pssqlite/
      SKILL.md
      examples/
        in-memory.PSSqliteConfig.yml
        wrapper-example.ps1
```

## Suggested skill file

Create `.github/skills/pssqlite/SKILL.md` with content like this:

```md
---
name: pssqlite
description: Use synedgy.PSSqlite for YAML-backed SQLite schema, initialisation, CRUD, and views.
argument-hint: What schema, table, view, or wrapper function do you want to create or update?
---

# When to use this skill

Use this skill when a PowerShell project wants:

- embedded SQLite without a separate database server
- YAML-defined schema and views
- config-backed CRUD wrapper functions
- direct SQL only for advanced cases

# Preferred workflow

1. Define or update a `*.PSSqliteConfig.yml` file.
2. Validate it with `Test-PSSqliteConfiguration`, then load it with `Get-PSSqliteDBConfig`.
3. Initialize the database with `Initialize-PSSqliteDatabase`.
4. Use:
   - `Get-PSSqliteRow`
   - `New-PSSqliteRow`
   - `Set-PSSqliteRow`
   - `Remove-PSSqliteRow`
5. Expose read models through `Schema.Views` and query them with `Get-PSSqliteRow`.
6. For destructive schema replacement, use `OVERWRITE` mode and rely on its default
   backup and compatible-data restore behaviour. Inspect restore errors and skipped data.

# Rules

- Prefer YAML schema over hand-written SQL for standard tables and views.
- Register https://synedgy.com/schemas/pssqlite-config.schema.json in the IDE.
- Runtime validation works on 5.1 and 7 and permits custom metadata; JSON Schema
  validation with Test-Json requires 7 and rejects unrecognised properties.
- Initialisation is not automatic schema diffing. Plan existing-table changes
  explicitly and test upgrades as well as fresh installation.
- Use Compare-PSSqliteDBVersion and Get-PSSqliteDBMetadata to check deployment;
  a version marker does not prove successful data restoration.
- Require effective filters for updates and deletes; empty filters affect all rows.
- Use -ErrorAction Stop for query/CRUD failures in transactional operations.
- Keep write operations table-based; use views for read/query shaping.
- Pass `$PSBoundParameters` into `ClauseData` or `RowData` in wrapper functions.
- Prefer structured `Schema.Views` definitions first, and use raw `Sql:` only for advanced SQLite view syntax.
- Do not pass `-NoPreserveData` unless the caller explicitly intends to discard all
  existing data.
- Use `Export-PSSqliteData` and `Import-PSSqliteData` for explicit backup/restore
  workflows outside database initialisation.
- Keep examples simple and aligned with the repository's real config-backed workflow.
```

## Schema replacement and data preservation

`Initialize-PSSqliteDatabase` preserves data by default when `MigrationMode` is
`OVERWRITE`:

```powershell
Initialize-PSSqliteDatabase -DatabaseConfig $config -MigrationMode OVERWRITE
```

Before replacing the database, the command creates:

- a complete SQLite backup named like
  `database_2026-08-19_11.49.35.bak.db`
- a JSON manifest named `_manifest.json`
- a timestamped JSON file for each user table

After creating the new schema, it restores tables and columns whose names still match.
Removed tables and columns are skipped, while new columns receive their configured
SQLite default or `NULL` where constraints permit. Row failures can leave partial
restoration, and recreation is not an atomic backup-to-restore operation. Retain
the complete SQLite backup and inspect import results before resuming writes.
Use `-NoPreserveData` only for an intentionally destructive
overwrite.

The JSON dump format is versioned independently from the configured database schema
version. `Import-PSSqliteData` currently accepts format version `1` only. This strict
check prevents newer or older dump structures from being interpreted incorrectly.
Import reads foreign-key metadata from the destination database, restores parent tables
before child tables, defers cyclic constraints, and verifies referential integrity before
committing.

## Minimal example for the examples folder

### `examples\in-memory.PSSqliteConfig.yml`

```yaml
ConnectionString: 'Data Source=:memory:;'
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
  Views:
    CarSummary:
      Columns:
        CarId:
          Source:
            Table: Cars
            Column: Id
        Description:
          Expression: Cars.Make || ' ' || Cars.Model
      From:
        Table: Cars
```

### `examples\wrapper-example.ps1`

```powershell
function Get-Car
{
    [CmdletBinding()]
    param
    (
        [string] $Make,
        [string] $Model,
        [string] $Colour
    )

    Get-PSSqliteRow -SqliteDBConfig (Get-MyModuleConfig) -TableName 'Cars' -ClauseData $PSBoundParameters
}

function New-Car
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [string] $Make,

        [Parameter(Mandatory)]
        [string] $Model,

        [string] $Colour
    )

    New-PSSqliteRow -SqliteDBConfig (Get-MyModuleConfig) -TableName 'Cars' -RowData $PSBoundParameters
}
```

## How to publish it for reuse

There is no general marketplace for repository skills. The most practical options are:

1. Keep this page as the source of truth for the skill content.
2. Publish a public repository that contains a copyable `.github/skills/pssqlite/` folder.
3. Reuse that folder through repository templates, scaffolding, or automation in consumer projects.

## Notes

For in-memory configuration, initialise using an explicit open connection and
keep it alive for subsequent CRUD calls, or supply a caller-owned transaction.
Do not initialise an in-memory store using an initializer-owned connection and
expect it to survive the call.

- Repository skills are discovered from the current repository, so each consuming project
  needs its own `.github/skills/pssqlite/` folder.
- If a consumer needs cross-repository or dynamic capabilities, an MCP server or plugin
  may be a better fit than a repository skill alone.
