# Resolving DLLs from NuGet packages

Restore the package graph from `synedgy.pssqlite.csproj` into the gitignored cache under `output\NuGetPackages`, then sync the module-shipped assets into `source\lib`:

```powershell
dotnet restore .\synedgy.pssqlite.csproj --packages .\output\NuGetPackages
./build.ps1 -Tasks Sync_Sqlite_Package_Assets
```

The runtime code must load from `source\lib`, not directly from the transient restore cache.

## Excluded RIDs

The following RIDs are excluded from the build process to avoid unnecessary dependencies and to keep the build lightweight:
- browser-wasm
- uap10.0
- win10-x86
- win10-x64
- win10-arm
- win10-arm64
- maccatalyst-x64
- maccatalyst-arm64
- linux-armel
- linux-mips64
- linux-riscv64
- linux-s390x
- linux-musl-s390x
- linux-ppc64le
