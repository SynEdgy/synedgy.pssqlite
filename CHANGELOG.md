# Changelog for synedgy.PSSqlite

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Basic CRUD support with `Get-PSSqliteRow`, `New-PSSqliteRow`,
  `Remove-PSSqliteRow`, `Set-PSSqliteRow`.
- SQL generation for create table statements with `Initialize-PSSqliteDatabase`.
- Version comparing with built-in `_metadata` table and `Compare-PSSqliteDBVersion`.
- Added changelog PR.
- YAML-defined SQLite view support, including structured `Schema.Views` definitions and a raw `Sql` escape hatch for advanced views.

### Changed

- Expanded README.md with the blog post reference plus config-driven usage and getting-started examples for schema, initialization, CRUD, views, and direct SQL queries.
- Added a WikiSource page documenting a reusable PSSqlite Copilot skill for consumer projects.
- Extended `Get-PSSqliteRow` so config-backed read operations can resolve declared views as well as tables.
- Added GitHub Copilot repository instructions, validation skill, and setup workflow.
- Documented how to avoid `output\module` file locks during rebuild and validation loops.
- Documented and automated the SQLite NuGet-to-`source\lib` dependency refresh flow, and hardened native SQLite preloading.
- Added config-backed CRUD regression tests and fixed metadata version lookup plus `Set-PSSqliteRow` connection cleanup.
- Marked macOS native SQLite libraries as binary in `.gitattributes` and refreshed the shipped `.dylib` assets to avoid cross-platform line-ending corruption.
