---
description: 'SQLite NuGet asset restore and preload instructions'
applyTo: '{synedgy.pssqlite.csproj,source/lib/**/*,source/ScriptsToProcess/*.ps1,.build/tasks/*.ps1,.build/modules/**/*.psm1,.build/README.md,.github/workflows/copilot-setup-steps.yml}'
---

# SQLite Dependency Asset Guidelines

## Source of truth

- Treat `synedgy.pssqlite.csproj` as the source of truth for SQLite-related NuGet package versions.
- Restore those packages into the gitignored `output\NuGetPackages` folder.
- Treat the committed `source\lib` folder as the runtime asset set that the module ships and imports from.

## Asset refresh flow

- Refresh SQLite assets with:

```powershell
dotnet restore .\synedgy.pssqlite.csproj --packages .\output\NuGetPackages
./build.ps1 -Tasks Sync_Sqlite_Package_Assets
```

- Copy only the managed assemblies and native runtime assets needed by supported PowerShell runtimes into `source\lib`.
- Do not point module runtime loading at `output\NuGetPackages`; copy the required files into `source\lib` first.

## Runtime compatibility

- Keep managed assemblies compatible with Windows PowerShell 5.1 and PowerShell 7.
- Keep native runtime assets for the PowerShell-compatible RIDs this module supports.
- Exclude UAP, browser, Catalyst, and unsupported Linux architecture assets from `source\lib`.
- Keep packaged native libraries marked as binary in `.gitattributes`, including `.dll`, `.so`, `.dylib`, and archive formats, so cross-platform artifacts are not line-ending normalized.

## Preload behavior

- `source\ScriptsToProcess\PreLoadTypes.ps1` must load the native SQLite library before `Microsoft.Data.Sqlite` types initialize.
- Resolve the native library by full path from `source\lib\runtimes\<rid>\native`.
- Surface missing or unloadable native libraries as explicit errors.

## Validation

- After refreshing package assets or preload logic, run:

```powershell
./build.ps1 -Tasks build
./build.ps1 -Tasks test
```
