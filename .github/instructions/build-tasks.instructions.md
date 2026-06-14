---
description: 'Build and workflow authoring instructions'
applyTo: '{build.ps1,build.yaml,.build/tasks/*.build.ps1,.pipelines/*.yml,.pipelines/*.yaml,.github/workflows/*.yml,.github/workflows/*.yaml}'
---

# Build and Workflow Development Guidelines

## Entry points

- Use `build.ps1` as the only bootstrap, build, and test entrypoint.
- Keep `build.ps1` focused on bootstrap and runtime parameters.
- Prefer changing `build.yaml` when altering workflow composition, copied assets, default test paths, or coverage behavior.
- If new local InvokeBuild task files are added later, place them under `.build\tasks\` and wire them through `build.yaml`.

## Dependency and environment rules

- Restore dependencies with `./build.ps1 -ResolveDependency -Tasks noop`.
- Restore SQLite NuGet packages with `dotnet restore .\synedgy.pssqlite.csproj --packages .\output\NuGetPackages` when package versions or packaged DLLs change.
- After restoring SQLite packages, sync the committed module assets with `./build.ps1 -Tasks Sync_Sqlite_Package_Assets`.
- Do not manually edit `PSModulePath`; let `build.ps1` handle it.
- Keep required modules resolving into `output\RequiredModules`.
- Keep the transient NuGet restore under `output\NuGetPackages` and the committed module assets under `source\lib`.
- Keep build artifacts flowing through `output\module` rather than ad-hoc locations.
- When validating long builds or tests, pipe `./build.ps1 ...` output through `Tee-Object` to a log outside `output\*`.

## Logging pattern

```powershell
$logPath = Join-Path -Path $env:TEMP -ChildPath 'synedgy.PSSqlite.validate-build.log'

if (Test-Path $logPath)
{
    Remove-Item $logPath -Force
}

./build.ps1 -Tasks build 2>&1 |
    Tee-Object -FilePath $logPath
```

- Do not wrap `./build.ps1` invocations in `| Select-Object -Last <N>` or other buffering filters.
- Read logs separately with `Get-Content -Tail` or `Select-String`.

## Task and pipeline safety

- Keep artifact context explicit when a workflow is packaging files from `lib`, `ScriptsToProcess`, or versioned module output.
- Reuse existing Sampler and ModuleBuilder patterns instead of re-deriving build paths or version information independently.
- Treat changes to `build.ps1`, `build.yaml`, `.build`, `.pipelines`, `.github/workflows`, `synedgy.pssqlite.csproj`, `source\lib`, or `source\ScriptsToProcess\PreLoadTypes.ps1` as validation-impacting changes.
- Run at least `./build.ps1 -Tasks test` after workflow wiring changes.
