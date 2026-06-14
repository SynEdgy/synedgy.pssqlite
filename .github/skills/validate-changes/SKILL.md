---
name: validate-changes
description: Run targeted synedgy.PSSqlite validation scopes quickly and safely, then widen validation only when the changed surface requires it.
argument-hint: What files or areas did you change, and how much validation do you want?
---

# Validate Changes

## Purpose

- Run the smallest useful validation scope first.
- Expand only when the changed surface requires it.

## Use this skill when

- You changed functions under `source/Public` or `source/Private`.
- You changed classes or enums under `source/Classes` or `source/Enum`.
- You changed type-accelerator behavior in `source/suffix.ps1`.
- You changed assembly preload behavior in `source/ScriptsToProcess/PreLoadTypes.ps1`, packaged libraries under `lib`, or `synedgy.pssqlite.csproj`.
- You changed build logic under `build.ps1`, `build.yaml`, `.build`, `.pipelines`, or `.github/workflows`.
- You need confidence before opening or updating a PR.

## Mandatory rule

Every validation command must go through `./build.ps1`.

- Do not run `Invoke-Pester` directly.
- Do not call `Build-Module` directly.
- Do not manually edit `PSModulePath`.
- Bootstrap dependencies with:

```powershell
./build.ps1 -ResolveDependency -Tasks noop
```

## Decision flow

1. If a specific test file is known, run only that file:

```powershell
./build.ps1 -Tasks test -PesterPath '<target_test>' -CodeCoverageThreshold 0
```

2. If changes are limited to one public or private function, run the matching unit test file under `tests/Unit/Public` or `tests/Unit/Private`.

3. If `source/suffix.ps1`, `source/Classes`, `source/Enum`, or `source/ScriptsToProcess/PreLoadTypes.ps1` changed, run focused tests first, then run the default test workflow:

```powershell
./build.ps1 -Tasks test
```

4. If build, workflow, packaging, or assembly wiring changed (`build.ps1`, `build.yaml`, `.build`, `.pipelines`, `.github/workflows`, `synedgy.pssqlite.csproj`, or `lib`), run:

```powershell
./build.ps1 -Tasks build
./build.ps1 -Tasks test
```

5. If packaging confidence is needed, run:

```powershell
./build.ps1 -Tasks pack
```

## Logging rule

For long-running builds or tests, tee output to a log outside `output\*`:

```powershell
$logPath = Join-Path -Path $env:TEMP -ChildPath 'synedgy.PSSqlite.validate-test.log'

if (Test-Path $logPath)
{
    Remove-Item $logPath -Force
}

./build.ps1 -Tasks test 2>&1 |
    Tee-Object -FilePath $logPath
```

- Do not use `| Select-Object -Last <N>` inline with `./build.ps1`.
- Inspect the log separately with `Get-Content -Tail` or `Select-String`.

## Completion checks

- The selected validation scope passed.
- Matching unit tests were updated for public or private function changes.
- Broader workflow validation ran when build wiring, package wiring, or class export behavior changed.
- `CHANGELOG.md` contains an `Unreleased` entry for user-visible or workflow-visible changes.
