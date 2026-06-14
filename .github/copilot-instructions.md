# Copilot instructions for synedgy.PSSqlite

## Build entrypoint

- Use `./build.ps1` for all dependency restore, build, test, and validation work.
- Bootstrap with `./build.ps1 -ResolveDependency -Tasks noop`.
- Build with `./build.ps1 -Tasks build`.
- Test with `./build.ps1 -Tasks test` or another named workflow from `build.yaml`.
- Do not call `Invoke-Pester`, `Build-Module`, or other build helpers directly from a fresh shell.
- Do not manually prepend `output/RequiredModules` or `output/module` to `PSModulePath`.

## Repository constraints

- The source module manifest is `source\synedgy.PSSqlite.psd1`.
- The built module is produced under `output\module`, and `build.yaml` keeps versioned output enabled.
- Keep required modules resolving into `output\RequiredModules`.
- SQLite package assets are restored from `synedgy.pssqlite.csproj` into a gitignored folder under `output\NuGetPackages`, then the required managed and native files are copied into `source\lib`.
- This module must remain compatible with Windows PowerShell 5.1 and PowerShell 7.
- `source\ScriptsToProcess\PreLoadTypes.ps1` is responsible for loading the native SQLite library and the managed SQLite assemblies before the rest of the module parses; changes there must preserve runtime and architecture resolution.
- `source\suffix.ps1` exports PowerShell classes through module-qualified type accelerators; changes there must preserve import and cleanup behavior.
- The primary consumer workflow is config-backed CRUD: load a `*.PSSqliteConfig.y*ml` file, initialize the database, and use wrapper functions that pass `$PSBoundParameters` into `ClauseData` or `RowData`.
- New or updated functions must keep comment-based help complete, including at least one `.EXAMPLE`, because `tests\QA\module.tests.ps1` enforces help coverage for exported functions.
- Add an `Unreleased` changelog entry in `CHANGELOG.md` for behavior or workflow changes.

## Instruction files

- Follow the targeted rules in `.github\instructions\*.instructions.md`.
- Use `.github\skills\validate-changes\SKILL.md` for validation scope selection.
