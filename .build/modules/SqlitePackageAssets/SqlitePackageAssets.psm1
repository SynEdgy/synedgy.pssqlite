function Get-LatestSqlitePackagePath
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $PackageId,

        [Parameter(Mandatory = $true)]
        [string]
        $PackageRoot
    )

    $packageDirectory = Join-Path -Path $PackageRoot -ChildPath $PackageId.ToLowerInvariant()

    if (-not (Test-Path -Path $packageDirectory))
    {
        throw "Package directory '$packageDirectory' was not found."
    }

    $versionDirectory = Get-ChildItem -Path $packageDirectory -Directory |
        Sort-Object -Property Name -Descending |
        Select-Object -First 1

    if (-not $versionDirectory)
    {
        throw "No package versions were found under '$packageDirectory'."
    }

    return $versionDirectory.FullName
}

function Copy-SqlitePackageFile
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $PackageId,

        [Parameter(Mandatory = $true)]
        [string]
        $RelativePath,

        [Parameter(Mandatory = $true)]
        [string]
        $DestinationDirectory,

        [Parameter(Mandatory = $true)]
        [string]
        $PackageRoot
    )

    $packagePath = Get-LatestSqlitePackagePath -PackageId $PackageId -PackageRoot $PackageRoot
    $sourcePath = Join-Path -Path $packagePath -ChildPath $RelativePath

    if (-not (Test-Path -Path $sourcePath))
    {
        throw "Expected package asset '$sourcePath' was not found."
    }

    Copy-Item -Path $sourcePath -Destination $DestinationDirectory -Force
}

function Sync-SqlitePackageAssets
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $ProjectFile,

        [Parameter(Mandatory = $true)]
        [string]
        $PackageRoot,

        [Parameter(Mandatory = $true)]
        [string]
        $LibRoot
    )

    $resolvedProjectFile = (Resolve-Path -Path $ProjectFile).Path
    $resolvedPackageRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PackageRoot)
    $resolvedLibRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LibRoot)

    Write-Host "Restoring NuGet packages for '$resolvedProjectFile' into '$resolvedPackageRoot'."

    & dotnet restore $resolvedProjectFile --packages $resolvedPackageRoot

    if ($LASTEXITCODE -ne 0)
    {
        throw "dotnet restore failed with exit code $LASTEXITCODE."
    }

    $managedTarget = Join-Path -Path $resolvedLibRoot -ChildPath 'netstandard2.0'
    $net461Target = Join-Path -Path $resolvedLibRoot -ChildPath 'net461'
    $runtimeTargetRoot = Join-Path -Path $resolvedLibRoot -ChildPath 'runtimes'

    foreach ($path in @($managedTarget, $net461Target, $runtimeTargetRoot))
    {
        if (Test-Path -Path $path)
        {
            Remove-Item -Path $path -Recurse -Force
        }

        $null = New-Item -Path $path -ItemType Directory -Force
    }

    $managedAssets = @(
        @{ PackageId = 'microsoft.data.sqlite.core'; RelativePath = 'lib\netstandard2.0\Microsoft.Data.Sqlite.dll' }
        @{ PackageId = 'microsoft.data.sqlite.core'; RelativePath = 'lib\netstandard2.0\Microsoft.Data.Sqlite.xml' }
        @{ PackageId = 'system.memory'; RelativePath = 'lib\netstandard2.0\System.Memory.dll' }
        @{ PackageId = 'system.memory'; RelativePath = 'lib\netstandard2.0\System.Memory.xml' }
        @{ PackageId = 'system.runtime.compilerservices.unsafe'; RelativePath = 'lib\netstandard2.0\System.Runtime.CompilerServices.Unsafe.dll' }
        @{ PackageId = 'system.runtime.compilerservices.unsafe'; RelativePath = 'lib\netstandard2.0\System.Runtime.CompilerServices.Unsafe.xml' }
        @{ PackageId = 'sqlitepclraw.core'; RelativePath = 'lib\netstandard2.0\SQLitePCLRaw.core.dll' }
        @{ PackageId = 'sqlitepclraw.provider.dynamic_cdecl'; RelativePath = 'lib\netstandard2.0\SQLitePCLRaw.provider.dynamic_cdecl.dll' }
        @{ PackageId = 'sqlitepclraw.provider.e_sqlite3'; RelativePath = 'lib\netstandard2.0\SQLitePCLRaw.provider.e_sqlite3.dll' }
        @{ PackageId = 'sqlitepclraw.bundle_e_sqlite3'; RelativePath = 'lib\netstandard2.0\SQLitePCLRaw.batteries_v2.dll' }
    )

    foreach ($asset in $managedAssets)
    {
        Copy-SqlitePackageFile -PackageId $asset.PackageId -RelativePath $asset.RelativePath -DestinationDirectory $managedTarget -PackageRoot $resolvedPackageRoot
    }

    Copy-SqlitePackageFile -PackageId 'sqlitepclraw.bundle_e_sqlite3' -RelativePath 'lib\net461\SQLitePCLRaw.batteries_v2.dll' -DestinationDirectory $net461Target -PackageRoot $resolvedPackageRoot

    $supportedRuntimeIds = @(
        'win-x86'
        'win-x64'
        'win-arm'
        'win-arm64'
        'linux-x86'
        'linux-x64'
        'linux-arm'
        'linux-arm64'
        'linux-musl-arm'
        'linux-musl-arm64'
        'linux-musl-x64'
        'osx-x64'
        'osx-arm64'
    )

    $nativePackagePath = Get-LatestSqlitePackagePath -PackageId 'sqlitepclraw.lib.e_sqlite3' -PackageRoot $resolvedPackageRoot

    foreach ($runtimeId in $supportedRuntimeIds)
    {
        $sourceRuntimePath = Join-Path -Path $nativePackagePath -ChildPath "runtimes\$runtimeId\native"

        if (-not (Test-Path -Path $sourceRuntimePath))
        {
            throw "Expected native runtime path '$sourceRuntimePath' was not found."
        }

        $targetRuntimePath = Join-Path -Path $runtimeTargetRoot -ChildPath "$runtimeId\native"
        $null = New-Item -Path $targetRuntimePath -ItemType Directory -Force

        Copy-Item -Path (Join-Path -Path $sourceRuntimePath -ChildPath '*') -Destination $targetRuntimePath -Force
    }

    Write-Host "SQLite package assets synced into '$resolvedLibRoot'."
}

Export-ModuleMember -Function Sync-SqlitePackageAssets
