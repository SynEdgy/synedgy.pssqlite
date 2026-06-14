---
description: 'Public function authoring instructions'
applyTo: 'source/Public/**/*.ps1'
---

# Public Function Development Guidelines

## Baseline structure

- Use comment-based help with:
  - `.SYNOPSIS`
  - `.DESCRIPTION`
  - at least one `.EXAMPLE`
  - `.PARAMETER` help for every parameter
- Use `[CmdletBinding()]`.
- Include `[OutputType(...)]` when the command returns a defined type or stable output shape.
- Use explicit parameter types where the command contract is stable.
- Keep parameter names and defaults stable unless intentionally making a breaking change.

## Public command rules

- Public functions are compatibility-sensitive.
- Preserve backward compatibility by default.
- Reuse existing helpers, classes, and enums instead of duplicating SQLite connection setup, SQL generation, or path resolution logic.
- Prefer routing raw query execution through `Invoke-PSSqliteQuery` and connection creation through `New-PSSqliteConnection`.
- Keep user-facing file, module, and configuration naming aligned with the existing `synedgy.PSSqlite` and `*.PSSqliteConfig.y*ml` patterns.
- If behavior, parameters, or output change, update help and the matching unit tests.

## Testing expectations

- Add or update matching tests under `tests\Unit\Public\<FunctionName>.tests.ps1`.
- Cover happy path and validation or failure behavior.
- Prefer in-memory SQLite connections for unit coverage unless file-backed behavior is the subject of the test.
- If command behavior depends on imported classes, type accelerators, or assembly preload, update the relevant QA or import coverage as well.
- Prefer focused validation first:

```powershell
./build.ps1 -Tasks test -PesterPath 'tests/Unit/Public/<FunctionName>.tests.ps1' -CodeCoverageThreshold 0
```

- User-visible behavior changes require an `Unreleased` changelog entry.
