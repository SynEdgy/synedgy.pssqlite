---
description: 'Pester test authoring instructions'
applyTo: 'tests/**/*.tests.ps1'
---

# Pester Tests Development Guidelines

## Baseline structure

- Follow the repository patterns in `tests\QA\module.tests.ps1` and `tests\Unit\Public\*.tests.ps1`.
- Use `BeforeDiscovery` for data-driven test cases.
- Put test-specific setup and mocks in the smallest practical `Describe` or `Context` scope.
- When a test needs the built module available from a fresh shell, bootstrap with `./build.ps1 -Tasks noop` instead of editing `PSModulePath`.

## Naming and assertions

- Start `It` descriptions with `Should` when creating or modernizing tests.
- Prefer the most specific assertion form available:
  - `Should -Be`
  - `Should -BeTrue` and `Should -BeFalse`
  - `Should -Throw` and `Should -Not -Throw`
  - `Should -BeNullOrEmpty` and `Should -Not -BeNullOrEmpty`
- Scope mock assertions to the smallest practical test scope.

## Repository-specific rules

- Keep tests consistent with the existing `tests\QA` and `tests\Unit\Public` patterns in this repository.
- When validating class or type-accelerator behavior, import the module before invoking code paths that reference exported accelerators.
- Use in-memory SQLite connections with `New-PSSqliteConnection` by default unless the scenario specifically requires a file-backed database.
- Use PowerShell-version or platform guards only when behavior truly differs between Windows PowerShell 5.1 and PowerShell 7, or between the runtime-specific native assemblies loaded by `PreLoadTypes.ps1`.

## Validation commands

```powershell
./build.ps1 -Tasks test -PesterPath 'tests/Unit/Public/<FunctionName>.tests.ps1' -CodeCoverageThreshold 0
./build.ps1 -Tasks test -PesterPath 'tests/QA/module.tests.ps1' -CodeCoverageThreshold 0
./build.ps1 -Tasks test
```
