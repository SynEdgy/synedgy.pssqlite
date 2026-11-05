# Configuration and validation

PSSqlite separates three concerns: the configuration's structure, its runtime
model invariants, and whether SQL can actually be applied to a particular database.
Neither editor validation nor the runtime validation cmdlet executes SQL.

## A complete configuration

Keep configuration in `config\<ModuleName>.PSSqliteConfig.yml` inside your module.
`Get-PSSqliteDBConfigFile` can discover this convention; an explicit path is useful
in deployment scripts and tests.

```yaml
# yaml-language-server: $schema=https://synedgy.com/schemas/pssqlite-config.schema.json
DatabasePath: '$Env:ProgramData\Example\Data'
DatabaseFile: 'Example.db'
Version: '1.0.0'
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
        CreatedOn:
          Type: TEXT
```

Provide `ConnectionString`, or both `DatabasePath` and `DatabaseFile`. An explicit
connection string takes precedence for connections, but file-backed initialisation
also uses the configured file paths to detect and recreate the database. Keep them
consistent. For `Data Source=:memory:;`, use an explicit open connection as shown
in [Database creation and CRUD](Database-creation-and-CRUD).

Property names are case-insensitive. Types are `INTEGER`, `TEXT`, `REAL` and `BLOB`.
The schema contains tables, views or ordered setup SQL. `Version` is your database
schema version, not the module version, SQLite engine version or backup format
version. Prefer integer versions or stable dotted versions such as `1.0.0`;
prerelease comparison differs between PowerShell editions.

## Published JSON Schema and IDE registration

The published, self-contained draft-07 JSON Schema is:

<https://synedgy.com/schemas/pssqlite-config.schema.json>

The module also ships a local copy in `schemas\pssqlite-config.schema.json`.
It describes tables, columns, constraints, indexes, structured/raw views and
`Schema.SetupSql`, with canonical property names for completion.

For VS Code with the Red Hat YAML extension, register this association in your
settings:

```json
{
  "yaml.schemas": {
    "https://synedgy.com/schemas/pssqlite-config.schema.json": [
      "**/*.PSSqliteConfig.yml",
      "**/*.PSSqliteConfig.yaml"
    ]
  }
}
```

Alternatively, use the `yaml-language-server` comment in the example above for a
single file. For offline editing, associate the local packaged schema file instead.
Other IDEs can register the same URL if they support JSON Schema validation of YAML.

The schema validates structure, not SQL syntax, cross-table references,
case-insensitive duplicate keys, unique setup names or migration safety.

### Validate YAML with Test-Json

`Test-Json` accepts JSON, so parse YAML first. This example requires PowerShell 7;
Windows PowerShell 5.1 does not provide `Test-Json`.

```powershell
Import-Module synedgy.PSSqlite -ErrorAction Stop

$yamlPath = '.\config\Example.PSSqliteConfig.yml'
$definition = ConvertFrom-Yaml -Yaml (Get-Content -LiteralPath $yamlPath -Raw -ErrorAction Stop) -Ordered -ErrorAction Stop
$json = $definition | ConvertTo-Json -Depth 100
$schema = (Invoke-WebRequest -Uri 'https://synedgy.com/schemas/pssqlite-config.schema.json' -ErrorAction Stop).Content

Test-Json -Json $json -Schema $schema -ErrorAction Stop
```

To use the packaged copy without a network request:

```powershell
$module = Get-Module -Name synedgy.PSSqlite
$schemaPath = Join-Path $module.ModuleBase 'schemas\pssqlite-config.schema.json'
Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction Stop
```

For reproducible CI, pin a local schema copy appropriate to the module version
you deploy; the hosted schema can evolve.

## PowerShell runtime validation

Use `Test-PSSqliteConfiguration` on either Windows PowerShell 5.1 or PowerShell 7:

```powershell
Test-PSSqliteConfiguration -Path '.\config\Example.PSSqliteConfig.yml'

$issues = @(Test-PSSqliteConfiguration -Path '.\config\Example.PSSqliteConfig.yml' -Detailed)
$issues | Format-Table Path, Code, Message -AutoSize
```

The default mode returns a Boolean and writes errors for invalid definitions.
`-ErrorAction Stop` makes those errors terminating, useful for CI or deployment:

```powershell
$null = Test-PSSqliteConfiguration -Path '.\config\Example.PSSqliteConfig.yml' -ErrorAction Stop
```

`-Detailed` returns diagnostics instead of a Boolean. No diagnostics means valid.
File access and malformed YAML are terminating errors in either mode, not
successful-looking validation results.

You can also validate an already parsed definition:

```powershell
Test-PSSqliteConfiguration -Definition $definition -Detailed
```

Runtime validation checks recognised properties before constructor coercion, then
reuses the model's checks, including constraint columns, table/view name collisions,
view requirements and unique setup names. It uses no additional validation DLLs.
It preserves the caller's definition and declaration order, does not expand
deployment variables, and does not open a database or execute setup SQL.
Semantic diagnostics can point to `$.Schema`; structural diagnostics include the
specific property path.

### Custom metadata and strict editor validation

Runtime validation **ignores unrecognised properties**, allowing documentation or
custom metadata at any configuration level. Recognised properties remain checked.
An unknown key does not substitute for a missing required key: `Tpye` does not
satisfy the required column `Type`.

The published JSON Schema is deliberately stricter and rejects unrecognised
properties. A file containing custom metadata can therefore pass runtime checks
while producing editor or `Test-Json` errors. These are different contracts, not
equivalent validators.

## Loading and deployment

```powershell
$config = Get-PSSqliteDBConfig -Path '.\config\Example.PSSqliteConfig.yml'
```

The YAML loader and dictionary constructor use the same runtime checks before
expanding paths and constructing the configuration. Loading does not create a
database. Deployment variables must be available when loading even though they
are not needed for validation.

Parameterless and connection-only constructors remain available for programmatic
use. Dictionary and YAML constructors expect complete configurations.

Next: [Database creation and CRUD](Database-creation-and-CRUD).
