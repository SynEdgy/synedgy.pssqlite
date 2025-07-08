# Changelog for synedgy.PSSqlite

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Basic CRUD support with `Get-PSSqliteRow`, `New-PSSqliteRow`,
  `Remove-PSSqliteRow`, `Set-PSSqliteRow`.
- SQL generation for create table statements with `Initialize-PSSqliteDatabase`.
- Version comparing with built-in `_metadata` table and `Compare-PSSqliteDBVersion`.

### Changed

- Updated README.md.
