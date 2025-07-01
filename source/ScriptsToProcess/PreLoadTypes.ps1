# List of types to load before importing the module
$assembliesToLoad = @(
    # This list should be loaded in the order they are listed
    'System.Runtime.CompilerServices.Unsafe.dll' # has to be 4.0.4.1 from nuget package version 4.5.3
    'System.Memory.dll'
    'SQLitePCLRaw.provider.e_sqlite3.dll'
    'SQLitePCLRaw.core.dll'
    'SQLitePCLRaw.batteries_v2.dll'
    'Microsoft.Data.Sqlite.dll'
)

if ($PSVersionTable.PSEdition -eq 'Desktop')
{
    # For .NET Framework, we need to load the SQLitePCLRaw provider
    $assembliesToLoad += 'SQLitePCLRaw.provider.dynamic_cdecl.dll' # Was needed for Windows PowerShell
}

# Add Native assemblies to process $Env:PATH
$moduleRoot = Split-Path -Path $PSScriptRoot -Parent
$libPath = Join-Path -Path $moduleRoot -ChildPath "lib"

# Determine the OS and architecture
if ($PSVersionTable.PSEdition -ne 'Core' -and [System.Environment]::Is64BitOperatingSystem)
{
    $arch = if ([System.Environment]::Is64BitOperatingSystem)
    {
        'x64'
        # Beware that Windows on ARM64 is effectively x86 emulation
    }
    else
    {
        'x86' # modern Windows doesn't have a ARM32 support
    }
}
else
{
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower()
}

$os = if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') { 'win' } elseif ($IsMacOS) { 'osx' } elseif ($IsLinux) { 'linux' } else { throw "Unsupported OS" }

$expectedRID = '{0}-{1}' -f $os, $arch
# Add the native assemblies to the PATH
$runtimesPath = Join-Path -Path $libPath -ChildPath 'runtimes'
$osRuntimePath = Join-Path -Path $runtimesPath -ChildPath $expectedRID
$nativePath = Join-Path -Path $osRuntimePath -ChildPath 'native'
if (-not (Test-Path -Path $nativePath))
{
    Write-Error -Message "Native path not found: $nativePath"
    return
}

# Add the native path to the environment PATH variable
if ($env:Path -split([io.path]::PathSeparator) -notcontains $nativePath)
{
    Write-Verbose -Message "Adding native path to environment PATH: $nativePath"
    $env:PATH = @($nativePath,$env:PATH) -join [io.path]::PathSeparator
}
else
{
    Write-Verbose -Message "Native path already exists in environment PATH: $nativePath"
}

# Load the managed assemblies in order
# TODO: Test if that works and remove the if block
$framework = if ($IsCoreCLR) { 'netstandard2.0' } else { 'netstandard2.0' } # or 'net461'
$managedAssembliesFolder = Join-Path -Path $libPath -ChildPath $framework
Write-Debug -Message "Managed assemblies folder: $managedAssembliesFolder"
if (-not (Test-Path -Path $managedAssembliesFolder))
{
    Write-Error -Message "Managed assemblies folder not found: $managedAssembliesFolder"
    return
}

$assembliesToLoad | ForEach-Object {
    $assemblyFileName = $_
    $assemblyPath = Join-Path -Path $managedAssembliesFolder -ChildPath $_
    if ([appdomain]::CurrentDomain.GetAssemblies().Where{$_.location -match ('{0}$' -f $assemblyFileName)})
    {
        Write-Verbose -Message "Assembly already loaded: $_"
    }
    else
    {
        if (Test-Path -Path $assemblyPath)
        {
            Write-Verbose -Message "Loading assembly: $assemblyPath"
            $null = [System.Reflection.Assembly]::LoadFrom($assemblyPath)
        }
        else
        {
            Write-Error -Message "Assembly not found: $assemblyPath"
        }
    }
}
