# PSSqlite Copilot Skill

This page documents a reusable Copilot skill for repositories that want to use
`synedgy.PSSqlite`.

## Goal

Use this skill in a consuming repository when you want Copilot to:

- define or update a `*.PSSqliteConfig.yml` schema
- initialize a SQLite database from YAML
- create wrapper functions that pass `$PSBoundParameters` into `ClauseData` or `RowData`
- use `Get-PSSqliteRow`, `New-PSSqliteRow`, `Set-PSSqliteRow`, and `Remove-PSSqliteRow`
- define read models with `Schema.Views`

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
description: Use synedgy.PSSqlite for YAML-backed SQLite schema, initialization, CRUD, and views.
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
2. Load it with `Get-PSSqliteDBConfig`.
3. Initialize the database with `Initialize-PSSqliteDatabase`.
4. Use:
   - `Get-PSSqliteRow`
   - `New-PSSqliteRow`
   - `Set-PSSqliteRow`
   - `Remove-PSSqliteRow`
5. Expose read models through `Schema.Views` and query them with `Get-PSSqliteRow`.

# Rules

- Prefer YAML schema over hand-written SQL for standard tables and views.
- Keep write operations table-based; use views for read/query shaping.
- Pass `$PSBoundParameters` into `ClauseData` or `RowData` in wrapper functions.
- Prefer structured `Schema.Views` definitions first, and use raw `Sql:` only for advanced SQLite view syntax.
- Keep examples simple and aligned with the repository's real config-backed workflow.
```

## Minimal example for the examples folder

### `examples\in-memory.PSSqliteConfig.yml`

```yaml
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

- Repository skills are discovered from the current repository, so each consuming project
  needs its own `.github/skills/pssqlite/` folder.
- If a consumer needs cross-repository or dynamic capabilities, an MCP server or plugin
  may be a better fit than a repository skill alone.
