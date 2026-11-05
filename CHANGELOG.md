# Changelog for synedgy.PSSqlite

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Packaged JSON Schema for PSSqlite YAML configuration, with editor association
  guidance for `https://synedgy.com/schemas/pssqlite-config.schema.json`.
- Ordered, named `Schema.SetupSql` statements for trusted custom schema setup,
  including FTS5 virtual tables and triggers.
- Caller-owned connection and transaction support for non-destructive
  initialisation, and typed transaction parameters for query, CRUD and metadata helpers.

### Fixed

- Emitted configured composite primary keys, foreign keys and checks, with
  table-level indexes generated as separate statements.
- Combined column constraints correctly, including `NOT NULL` with defaults,
  uniqueness, checks, collation and inline references.
- Retained multiple table options, generated `WITHOUT ROWID` correctly, and honoured
  configured primary key ordering and table `IfNotExists`.
- Applied generated schema, custom setup SQL and schema version metadata atomically.
- Bound query null parameters as SQL NULL, disposed query resources on failure,
  and returned usable, buffered `DataReader` results.
- Compared integer schema versions consistently across PowerShell editions.
- Configured the release changelog pull request with an explicit Git identity and
  `CHANGELOG.md` staging path, and removed its duplicate pipeline invocation.
- Restored stable release history from GitHub publication dates and tagged commits,
  removing already-released changes from `Unreleased`. Prerelease history remains
  available on the [GitHub releases page](https://github.com/SynEdgy/synedgy.pssqlite/releases).
- Made full Git history and tag checkout explicit for version calculation and
  release changelog automation.

## [0.3.0] - 2026-10-08

### Added

- YAML-defined SQLite view support, including structured `Schema.Views` definitions and a raw `Sql` escape hatch for advanced views.
- Timestamped JSON table-data export and schema-tolerant, foreign-key-aware import, with default data preservation and a complete database backup during overwrite migrations.
- Added a WikiSource page documenting a reusable PSSqlite Copilot skill for consumer projects.
- Added GitHub Copilot repository instructions, validation skill, and setup workflow.
- Added config-backed CRUD regression tests.

### Changed

- Aligned all packaged SQLitePCLRaw assemblies to version 2.1.10 and registered RID-specific native library resolution for Windows PowerShell and cross-platform compatibility.
- Expanded README.md with the blog post reference plus config-driven usage and getting-started examples for schema, initialization, CRUD, views, and direct SQL queries.
- Extended `Get-PSSqliteRow` so config-backed read operations can resolve declared views as well as tables.
- Documented how to avoid `output\module` file locks during rebuild and validation loops.
- Documented and automated the SQLite NuGet-to-`source\lib` dependency refresh flow, and hardened native SQLite preloading.

### Fixed

- Avoided force-loading the bundled native `e_sqlite3` library when it is already loaded in the host process, including platforms that do not expose native handles through `Process.Modules`, preventing conflicts with hosts such as PowerShell Universal while retaining bundled-library loading when required.
- Fixed metadata version lookup and `Set-PSSqliteRow` connection cleanup.
- Marked macOS native SQLite libraries as binary in `.gitattributes` and refreshed the shipped `.dylib` assets to avoid cross-platform line-ending corruption.

## [0.2.2] - 2025-11-11

### Fixed

- Fixed table-definition lookup in `Remove-PSSqliteRow` and `Set-PSSqliteRow`
  so operations can target tables other than the first configured table.
- Enabled the release changelog pull request task in the publish workflow.

## [0.2.1] - 2025-11-11

### Changed

- Standardised the module name casing to `synedgy.PSSqlite` and updated the README.

### Fixed

- Fixed table-definition lookup in `Get-PSSqliteRow` so reads can target tables
  other than the first configured table.
- Corrected the exported deletion command name to `Remove-PSSqliteRow`.

## [0.2.0] - 2025-07-01

### Added

- SQLite connection creation and parameterised SQL execution with configurable
  result formats through `New-PSSqliteConnection` and `Invoke-PSSqliteQuery`.
- YAML-backed database configuration, table schema generation and initialisation
  through `Get-PSSqliteDBConfig` and `Initialize-PSSqliteDatabase`.
- Config-backed row creation, reading, updating and deletion.
- Schema version comparison using the `_metadata` table and `Compare-PSSqliteDBVersion`.

### Changed

- Made CRUD filtering case-insensitive by default and updated comment-based help.

[Unreleased]: https://github.com/SynEdgy/synedgy.pssqlite/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/SynEdgy/synedgy.pssqlite/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/SynEdgy/synedgy.pssqlite/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/SynEdgy/synedgy.pssqlite/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/SynEdgy/synedgy.pssqlite/releases/tag/v0.2.0
