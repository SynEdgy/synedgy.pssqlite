# synedgy.PSSqlite

`synedgy.PSSqlite` provides embedded SQLite for PowerShell applications, with
YAML-defined schema, config-backed CRUD commands and direct SQL when needed.
The module and runtime configuration validation support Windows PowerShell 5.1
and PowerShell 7.

Start with these guides:

- [Configuration and validation](Configuration-and-validation): YAML, the
  published JSON Schema, IDE registration and PowerShell validation.
- [Database creation and CRUD](Database-creation-and-CRUD): initialisation,
  constraints, views, filtering, custom SQL and connection/transaction ownership.
- [Schema upgrades and recovery](Schema-upgrades-and-recovery): metadata,
  version checks, additive upgrades, recreation, backups and import caveats.
- [PSSqlite Copilot skill](PSSqlite-Copilot-Skill): a copyable skill for consuming
  repositories.

Configuration validation is not SQL validation. A schema version marker records
an applied version, not proof that an existing database matches every YAML field.
Read the upgrade guide before changing a deployed schema.
