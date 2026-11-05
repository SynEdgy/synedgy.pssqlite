# Schema upgrades and recovery

Changing YAML and increasing `Version` does not by itself reconcile an existing
database. Plan the transition, take a backup and test against representative data.

## Metadata and version checks

PSSqlite stores custom metadata in `_metadata (key, value)`. Initialisation writes
the YAML schema `version` only after generated schema and setup SQL succeed.
This is independent of the module version, SQLite's engine version and JSON dump
`FormatVersion`.

```powershell
$config = Get-PSSqliteDBConfig -Path '.\config\Example.PSSqliteConfig.yml'
$comparison = Compare-PSSqliteDBVersion -DatabaseConfig $config -ErrorAction Stop
$comparison | Format-List CurrentVersion, ExpectedVersion, IsDeployed, direction, Reasons
```

`direction` compares the **database** version to the expected configuration:

| Direction | Meaning |
|---|---|
| `==` | Versions match. |
| `<` | Database version is older. |
| `>` | Database version is newer. |
| `!=` | No usable deployed marker, or versions differ without an ordered result. Check `Reasons`. |

`IsDeployed` means a version marker was found; it is not a full schema inspection.
Use `-ExpectedVersion` to override the configuration version for a check.
Prefer stable dotted or integer schema versions across 5.1 and 7; Windows
PowerShell comparison strips prerelease tags.

To retrieve all metadata or selected keys:

```powershell
$connection = New-PSSqliteConnection -ConnectionString $config.ConnectionString
try
{
    Get-PSSqliteDBMetadata -SqliteConnection $connection -MetadataKey version -ErrorAction Stop
}
finally
{
    $connection.Dispose()
}
```

For an existing open connection, use `-KeepAlive`, or provide its
`-SqliteTransaction` to read metadata inside your transaction. Version comparison
also accepts the caller's connection and transaction. Avoid manually changing the
version marker to bypass a failed migration.

## Non-destructive additive upgrades

For adding a new table or index:

1. Retain existing definitions and add the new table/index to YAML.
2. Increase `Version`, validate and load the new configuration.
3. Back up the existing database while writers are stopped.
4. Apply `INCREMENTAL`, then check the deployed version and application behaviour.

```powershell
$null = Test-PSSqliteConfiguration -Path '.\config\Example.PSSqliteConfig.yml' -ErrorAction Stop
$newConfig = Get-PSSqliteDBConfig -Path '.\config\Example.PSSqliteConfig.yml'
Initialize-PSSqliteDatabase -DatabaseConfig $newConfig -MigrationMode INCREMENTAL -ErrorAction Stop
Compare-PSSqliteDBVersion -DatabaseConfig $newConfig -ErrorAction Stop
```

This does not delete the database file. Current/newer versions are skipped.
It is **not a schema-diff engine**: changing an existing column, constraint, view
or index definition is not applied by `IF NOT EXISTS`. A marker can advance even
though such an edit did not alter the existing object.

For changes to an existing object, provide reviewed upgrade SQL through
`Schema.SetupSql`, or deliberately recreate and restore data. The module does not
calculate ALTER statements, keep per-step migration history or choose a chain of
scripts based on the starting version.

### Explicit upgrade SQL and fresh databases

An upgrade must work both on the supported old database versions and on a fresh
database/recreation. Simply adding `ALTER TABLE Cars ADD COLUMN ...` while also
adding that column to YAML causes a fresh installation to attempt adding an
already-created column. Historical upgrade blocks can similarly fail when rerun.

SQLite does not support `ADD COLUMN IF NOT EXISTS`. For a nullable `Notes TEXT`
column added to the YAML `Cars` definition in version `2.0.0`, an application can
inspect the existing schema before applying the change. This bounded example
supports a fresh database, version `1.0.0`, and an already deployed `2.0.0`;
it rejects other deployed versions and unversioned existing `Cars` tables.
It assumes writers are stopped and a backup already exists:

```powershell
$newConfig = Get-PSSqliteDBConfig -Path '.\config\Example.PSSqliteConfig.yml'
if ($newConfig.Version -ne '2.0.0')
{
    throw 'This migration requires configuration version 2.0.0.'
}

$connection = New-PSSqliteConnection -ConnectionString $newConfig.ConnectionString
$connection.Open()
$transaction = $null
try
{
    $transaction = $connection.BeginTransaction()
    $owned = @{
        SqliteConnection = $connection
        SqliteTransaction = $transaction
        ErrorAction = 'Stop'
    }

    $comparison = Compare-PSSqliteDBVersion -DatabaseConfig $newConfig @owned
    if ($comparison.IsDeployed -and $comparison.CurrentVersion -notin @('1.0.0', '2.0.0'))
    {
        throw 'Unsupported starting schema version.'
    }

    $columns = @(Invoke-PSSqliteQuery @owned -CommandText "PRAGMA table_info('Cars');" -As PSCustomObject)
    if ($columns.Count -gt 0 -and -not $comparison.IsDeployed)
    {
        throw 'Existing Cars table has no deployed version marker.'
    }

    if ($comparison.IsDeployed -and $columns.Count -eq 0)
    {
        throw 'Deployed schema is missing the Cars table.'
    }

    if ($comparison.CurrentVersion -eq '1.0.0' -and 'Notes' -notin $columns.name)
    {
        $null = Invoke-PSSqliteQuery @owned -CommandText 'ALTER TABLE Cars ADD COLUMN Notes TEXT;'
    }

    Initialize-PSSqliteDatabase -DatabaseConfig $newConfig @owned
    $columns = @(Invoke-PSSqliteQuery @owned -CommandText "PRAGMA table_info('Cars');" -As PSCustomObject)
    if ('Notes' -notin $columns.name)
    {
        throw 'Migration did not produce the expected Notes column.'
    }

    $transaction.Commit()
}
catch
{
    if ($transaction) { $transaction.Rollback() }

    throw
}
finally
{
    if ($transaction) { $transaction.Dispose() }

    $connection.Dispose()
}
```

On a fresh database, initialisation creates `Cars` with `Notes` from YAML.
On `1.0.0`, the ALTER and new version marker share the caller's transaction.
For other changes, inspect the expected old/new column types and constraints too;
column presence alone is not comprehensive schema validation.

The application owns starting-version checks, transformation logic and recovery.
Configure connection PRAGMAs before starting the transaction, not inside `SetupSql`.
For changes SQLite cannot express with ALTER, a tested replacement-table/data-copy
script or deliberate recreation can be required. Check dependent indexes,
triggers, views and foreign keys; there is no generic safe rebuild script.

Keep setup SQL idempotent for recreation, test every supported upgrade path, and
test fresh installation. Treat the YAML as trusted code.

## Recreation with compatible-data preservation

When recreation is appropriate:

```powershell
Initialize-PSSqliteDatabase -DatabaseConfig $newConfig -MigrationMode OVERWRITE -DataBackupPath '.\backups\before-upgrade' -ErrorAction Stop
```

On an applicable overwrite, the initializer:

1. Creates a complete SQLite backup for a file-backed database, named like
   `Example_2026-11-05_12.00.00.bak.db`.
2. Exports a JSON manifest and per-table data files.
3. Removes the original database file and creates the new schema.
4. Imports compatible data by matching table and column names.

The default backup directory is timestamped beside the database. A backup path
with an existing `_manifest.json` is rejected; use a new directory. `-Force`
selects recreation even at the current version.

**This whole workflow is not one atomic transaction.** Schema application is atomic;
file backup, deletion, recreation and import are separate steps. Import can fail
after the new schema/version has been committed. Keep the complete database backup
until data and application checks pass; a matching version marker does not prove
successful restoration.

`-NoPreserveData` skips backup, export and restoration and permanently removes
existing data. Use it only when discarding data is explicitly intended.
Overwrite is not supported with a supplied caller-owned connection/transaction.

## Explicit backup and import

`Export-PSSqliteData` creates a portable **data dump**, not a complete SQLite backup:

```powershell
Export-PSSqliteData -SqliteDBConfig $config -Path '.\backups\before-upgrade' -ErrorAction Stop
```

The directory contains `_manifest.json` and timestamped JSON files for user
tables. Existing manifests require `-Force` to replace. BLOB values are Base64
encoded. Views, `sqlite_*` tables and `_metadata` are excluded; indexes, triggers
and schema definitions are not preserved by the JSON dump.

For a complete standalone file backup, use SQLite's backup API rather than
copying a live `.db` file without its WAL state:

```powershell
$source = New-PSSqliteConnection -ConnectionString $config.ConnectionString
$destination = New-PSSqliteConnection -DatabasePath '.\backups' -DatabaseFile 'before-upgrade.bak.db'
try
{
    $source.Open()
    $destination.Open()
    $source.BackupDatabase($destination)
}
finally
{
    $destination.Dispose()
    $source.Dispose()
}
```

Create the backup directory first and choose a new destination filename.
Stop application writers for an upgrade so that no changes are lost between
backup/export and migration. JSON export reads tables separately, without a
single database-wide snapshot; concurrent writes can produce an inconsistent dump.
FTS virtual/shadow tables and custom SQLite extensions need a feature-specific
backup/restore plan rather than assuming ordinary-table JSON restoration is adequate.

Import into an initialised destination:

```powershell
$results = @(Import-PSSqliteData -SqliteDBConfig $newConfig -Path '.\backups\before-upgrade' -ErrorAction Continue)
$results | Format-Table TableName, Attempted, Imported, Failed, Status -AutoSize

if (@($results | Where-Object Failed -gt 0).Count -gt 0)
{
    throw 'Some rows were not restored. Inspect import errors and keep the backup.'
}
```

Inspect skipped-table/column statuses as well as failures; a zero failure count
does not mean all source data was retained. Import currently accepts dump
`FormatVersion: 1` only.

### Import caveats

- Import uses **INSERT**, not upsert, replacement or merge. Prefer an empty
  destination; importing twice can cause duplicate-key errors.
- Table/column matching is case-insensitive. Removed tables/columns are skipped;
  new columns receive SQLite defaults or NULL. Renames and data transformations
  are not inferred.
- New `NOT NULL`, unique, check or type constraints can reject old data.
  Defaults do not automatically fix incompatible copied values.
- Compatible row imports can continue after individual failures when errors are
  non-terminating. With `-ErrorAction Continue`, successful rows can be committed
  while other rows fail: **partial success is possible**. Inspect per-table results
  and error output. `-ErrorAction Stop` aborts on the first row error and rolls back
  the import transaction.
- Destination foreign keys determine parent-before-child order. Cyclic constraints
  are deferred; `PRAGMA foreign_key_check` must pass before commit. Violations
  roll back the import transaction.
- Import manages its own transaction and accepts an optional connection, not a
  caller-owned `SqliteTransaction`. Do not nest it in the CRUD transaction example.

## Recovery

On failure, stop writers and close/dispose database connections before restoring.
Recover the complete database backup to the original location using an
application-controlled, SQLite-aware procedure; do not blindly overwrite an open
database or ignore existing WAL/SHM sidecars. Keep the old YAML/application version
with the backup so schema and code remain aligned.

Test restore procedures before production use. A portable JSON dump is useful for
compatible-data migration; the complete SQLite backup is the stronger recovery
artefact when schema replacement fails.
