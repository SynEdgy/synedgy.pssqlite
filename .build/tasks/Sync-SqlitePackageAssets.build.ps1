$sqlitePackageAssetsModulePath = Join-Path -Path $BuildRoot -ChildPath '.build\modules\SqlitePackageAssets\SqlitePackageAssets.psm1'

Import-Module -Name $sqlitePackageAssetsModulePath -Force -ErrorAction Stop

task Sync_Sqlite_Package_Assets {
    $projectFile = Join-Path -Path $BuildRoot -ChildPath 'synedgy.pssqlite.csproj'
    $packageRoot = Join-Path -Path $BuildRoot -ChildPath 'output\NuGetPackages'
    $libRoot = Join-Path -Path $BuildRoot -ChildPath 'source\lib'

    Sync-SqlitePackageAssets -ProjectFile $projectFile -PackageRoot $packageRoot -LibRoot $libRoot
}
