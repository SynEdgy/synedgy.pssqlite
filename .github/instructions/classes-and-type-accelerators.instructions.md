---
description: 'Module class export and assembly preload instructions'
applyTo: '{source/suffix.ps1,source/Classes/*.ps1,source/Enum/*.ps1,source/ScriptsToProcess/*.ps1,source/synedgy.PSSqlite.psm1}'
---

# Classes, Type Accelerators, and Assembly Preload Guidelines

## Purpose

- This repository uses `source\suffix.ps1` to expose selected PowerShell classes after module import.
- This repository uses `source\ScriptsToProcess\PreLoadTypes.ps1` to load managed and native SQLite assemblies before the module imports.

## Type accelerator rules

- Keep type-accelerator registration in `source\suffix.ps1`, after classes are available.
- Prefer module-qualified accelerators to reduce name collisions.
- Resolve the module name with `Get-CurrentModule` rather than hard-coding it.
- Validate that each type exists before registering its accelerator.
- Warn when overriding an existing accelerator and fail when the target type cannot be found.

## Assembly preload rules

- Keep the assembly list in `source\ScriptsToProcess\PreLoadTypes.ps1` ordered when load order matters.
- Preserve the runtime identifier and architecture resolution logic for Desktop and Core editions.
- Preserve the behavior that prepends the resolved native runtime folder to `PATH`.
- Fail explicitly when expected runtime or managed assembly folders are missing; do not add silent fallbacks.

## Cleanup rules

- Remove registered type accelerators in the module `OnRemove` handler.
- Keep cleanup logic aligned with the accelerators registered during import.

## Usage implications

- Module consumers must import the module before invoking code paths that depend on exported type accelerators.
- Module consumers must import the module before invoking code paths that depend on the preloaded SQLite assemblies.
- Keep this pattern compatible with Windows PowerShell 5.1 and PowerShell 7.

## Change safety

- When adding, removing, or renaming exported classes, update:
  - `source\suffix.ps1`
  - the relevant class files under `source\Classes\`
  - any tests that instantiate or reference those classes
- When changing preload behavior, update the relevant tests and validate module import behavior.
- Preserve the current collision-avoidance behavior unless intentionally redesigning class consumption.
