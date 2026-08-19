# Incremental schema migration implementation plan

This document describes the remaining planned design for applying SQLite schema
changes incrementally. Data-preserving `OVERWRITE` migrations are now implemented,
but true in-place schema diffing and table rebuilds remain future work.

Status: **partially implemented**. Automatic backup, JSON export/import, and
compatible-data restoration are complete. Incremental column and constraint
migrations described below are not yet implemented.

## Implemented overwrite safety

`Initialize-PSSqliteDatabase -MigrationMode OVERWRITE` now preserves data by
default. Before replacing a file-backed database, it creates:

- a complete SQLite backup named like
  `database_2026-08-19_11.49.35.bak.db`
- `_manifest.json`
- one timestamped JSON file per user table

The new schema is then created and `Import-PSSqliteData` restores matching
tables and columns. Removed tables and columns are skipped; new columns use
their SQLite defaults. `-NoPreserveData` opts into the former destructive
behavior.

The JSON dump `FormatVersion` is separate from the configured database schema
version. Import currently accepts format version `1` only so unsupported dump
structures fail explicitly.

## Problem statement

`Initialize-PSSqliteDatabase` supports three `DBMigrationMode` values
(`INCREMENTAL`, `CREATE`, `OVERWRITE`), and the database already tracks a
schema version in a `_metadata` table (see `Get-PSSqliteDBMetadata`,
`Compare-PSSqliteDBVersion`).

However, `INCREMENTAL` mode's `[SQLiteDBConfig]::updateDBSchema()`
(`source/Classes/20.SqliteDBConfig.ps1`) only re-runs the generated SQL, and
every table is emitted as `CREATE TABLE IF NOT EXISTS ...`
(`source/Classes/07.SqliteTable.ps1`, `CreateString()`). If the table already
exists, `IF NOT EXISTS` means the statement is a no-op: new or changed
columns declared in the YAML config are silently ignored.

The only mode that actually applies structural changes today is `OVERWRITE`,
which calls `removeDatabase()` (deletes the `.db` file) and `createDatabase()`
(recreates from scratch). It is currently the only way consumers can pick up
schema changes to existing tables, but it now backs up and restores compatible
data automatically.

## Target behavior

Replace the blind re-run in `updateDBSchema()` with a per-table diff-and-apply
strategy, so that:

1. New tables are created as today (no change).
2. Purely additive column changes to existing tables are applied in place
   without data loss, via `ALTER TABLE ... ADD COLUMN`.
3. Structural changes that SQLite cannot `ALTER` in place (type change,
   column removal, PK/constraint change) are applied via a table rebuild
   that preserves data in common columns.
4. Reuse the implemented backup/export path before any future destructive
   rebuild, so a failed or unwanted migration is recoverable.
5. `_metadata.version` continues to be bumped only after a successful
   migration (existing behavior, unchanged).

## Design

### 1. Schema diffing

Add a `Compare-PSSqliteTableSchema` function (or method on `SqliteTable`)
that compares the live database against the declared config for a single
table:

- Live side: `PRAGMA table_info(<table>)` gives name, type, `notnull`,
  `dflt_value`, `pk` for each existing column. `PRAGMA index_list` /
  `PRAGMA foreign_key_list` can be added later if constraint diffing is
  needed.
- Declared side: the existing `SqliteTable.Columns` (`SqliteColumn[]`)
  parsed from YAML/config.

Output a diff object per table:

- `IsNewTable` - table absent from `sqlite_master`.
- `AddedColumns` - declared, not present live.
- `RemovedColumns` - present live, not declared.
- `ChangedColumns` - same name, different type / notnull / default / pk.

### 2. Strategy selection per table

- **New table** -> existing `CREATE TABLE IF NOT EXISTS` path, unchanged.
- **Only `AddedColumns`** (no removed/changed columns) -> additive path:
  emit `ALTER TABLE <t> ADD COLUMN <colDef>` per added column.
  - Validate before emitting: SQLite disallows adding a column that is
    `PRIMARY KEY` or `UNIQUE`, and a `NOT NULL` added column must have a
    non-null `DEFAULT`. Reject with a clear error instead of emitting SQL
    that SQLite would refuse.
- **Any `RemovedColumns` or `ChangedColumns`** -> rebuild path (below).

### 3. Rebuild path (for non-additive changes)

Standard SQLite 12-step pattern, run inside a single transaction so a
failure rolls back cleanly and never leaves a half-migrated file:

1. `PRAGMA foreign_keys=OFF`
2. `BEGIN TRANSACTION`
3. `CREATE TABLE <t>_new (...)` using the newly declared schema
4. `INSERT INTO <t>_new (commonCols) SELECT commonCols FROM <t>` -
   this is the actual data-preservation step. Columns not in common
   (dropped) are left out; new columns get their `DEFAULT` or `NULL`.
5. `DROP TABLE <t>`
6. `ALTER TABLE <t>_new RENAME TO <t>`
7. Recreate any indexes/views tied to `<t>` (implicitly dropped with the
   old table)
8. `PRAGMA foreign_key_check`
9. `COMMIT`, then `PRAGMA foreign_keys=ON`

### 4. Renames require an explicit hint

A rename is indistinguishable from "drop old column + add new column" from
a diff's perspective, and data would be silently lost if treated as such.
Add an optional `RenamedFrom` property on `SqliteColumn`, settable in YAML:

```yaml
roomName:
  type: TEXT
  renamedFrom: room_name
```

The diff/rebuild logic consults `RenamedFrom` to map old -> new column
names in the rebuild's `INSERT ... SELECT`, instead of treating it as a
drop and an add.

### 5. Backup before any destructive operation

Reuse the existing overwrite migration protection:

- a complete backup created through `SqliteConnection.BackupDatabase()`
- a versioned JSON dump created by `Export-PSSqliteData`
- schema-tolerant restoration through `Import-PSSqliteData`

Future incremental table rebuilds should invoke the same protection before
executing destructive DDL.

### 6. Wiring into existing code

`Initialize-PSSqliteDatabase`'s `INCREMENTAL` branch already gates on
`Compare-PSSqliteDBVersion`. Replace the body of
`[SQLiteDBConfig]::updateDBSchema()` (currently one blind
`GetSchemaSDL()` re-run) with:

1. Create the complete database backup and JSON export
2. Per-table diff via `Compare-PSSqliteTableSchema`
3. Additive `ALTER` or rebuild per table, as determined above
4. Bump `_metadata.version` (existing behavior)

`OVERWRITE` mode is updated to always call `Backup-PSSqliteDatabase` first,
so "delete and recreate" is never irreversible.

## Open questions / follow-ups

- Should constraint-only changes (e.g. adding an index, changing a
  `UNIQUE`/`CHECK` clause) be diffed and handled additively (index
  create/drop is cheap and non-destructive), or always routed through the
  rebuild path for simplicity?
- Do we need a dry-run / `-WhatIf` mode that reports the diff and planned
  SQL without applying it, for operators to review before a production
  migration?
- Pester coverage should include one test per diff scenario: add column,
  drop column, type change, explicit rename via `RenamedFrom`, and a
  combined add+drop+change in a single migration.

## References

- `source/Enum/DBMigrationMode.ps1`
- `source/Public/config/Initialize-PSSqliteDatabase.ps1`
- `source/Classes/20.SqliteDBConfig.ps1` (`updateDBSchema`, `createDatabase`,
  `removeDatabase`)
- `source/Classes/07.SqliteTable.ps1` (`CreateString`)
- `source/Classes/06.SqliteColumn.ps1`
- `source/Public/utils/Compare-PSSqliteDBVersion.ps1`
- `source/Public/utils/Get-PSSqliteDBMetadata.ps1`
