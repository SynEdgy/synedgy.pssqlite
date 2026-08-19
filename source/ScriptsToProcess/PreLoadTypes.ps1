# List of types to load before importing the module
$assembliesToLoad = @(
    # This list should be loaded in the order they are listed
    'System.Runtime.CompilerServices.Unsafe.dll' # has to be 4.0.4.1 from nuget package version 4.5.3
    'System.Memory.dll'
    'SQLitePCLRaw.core.dll'
    'SQLitePCLRaw.provider.e_sqlite3.dll'
    'SQLitePCLRaw.batteries_v2.dll'
    'Microsoft.Data.Sqlite.dll'
)

if ($PSVersionTable.PSEdition -eq 'Desktop')
{
    # For .NET Framework, we need to load the SQLitePCLRaw provider
    $assembliesToLoad += 'SQLitePCLRaw.provider.dynamic_cdecl.dll' # Was needed for Windows PowerShell
}

function Import-NativeSqliteLibrary
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $NativeLibraryPath
    )

    if (-not (Test-Path -Path $NativeLibraryPath))
    {
        throw "Native SQLite library not found: $NativeLibraryPath"
    }

    if ($IsCoreCLR)
    {
        Write-Verbose -Message "Loading native SQLite library: $NativeLibraryPath"
        $handle = [System.Runtime.InteropServices.NativeLibrary]::Load($NativeLibraryPath)
    }
    else
    {
        if (-not ('Win32.NativeLibraryLoader' -as [type]))
        {
            Add-Type -Namespace Win32 -Name NativeLibraryLoader -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern System.IntPtr LoadLibrary(string fileName);
'@
        }

        Write-Verbose -Message "Loading native SQLite library: $NativeLibraryPath"
        $handle = [Win32.NativeLibraryLoader]::LoadLibrary($NativeLibraryPath)

        if ($handle -eq [System.IntPtr]::Zero)
        {
            $lastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Failed to load native SQLite library '$NativeLibraryPath'. Win32 error: $lastError"
        }
    }

    return $handle
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
$nativeLibraryName = if ($os -eq 'win') { 'e_sqlite3.dll' } elseif ($os -eq 'osx') { 'libe_sqlite3.dylib' } else { 'libe_sqlite3.so' }
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

$nativeLibraryPath = Join-Path -Path $nativePath -ChildPath $nativeLibraryName
$nativeLibraryHandle = Import-NativeSqliteLibrary -NativeLibraryPath $nativeLibraryPath

if ($IsCoreCLR -and -not ('PSSqlite.NativeLibraryResolver' -as [type]))
{
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.InteropServices;

namespace PSSqlite
{
    public static class NativeLibraryResolver
    {
        private static readonly HashSet<Assembly> RegisteredAssemblies = new HashSet<Assembly>();

        public static void Register(Assembly assembly, IntPtr nativeLibraryHandle)
        {
            lock (RegisteredAssemblies)
            {
                if (RegisteredAssemblies.Contains(assembly))
                {
                    return;
                }

                NativeLibrary.SetDllImportResolver(
                    assembly,
                    (libraryName, requestingAssembly, searchPath) =>
                    {
                        if (string.Equals(libraryName, "e_sqlite3", StringComparison.Ordinal))
                        {
                            return nativeLibraryHandle;
                        }

                        return IntPtr.Zero;
                    });

                RegisteredAssemblies.Add(assembly);
            }
        }
    }
}
'@
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
    $loadedAssembly = [appdomain]::CurrentDomain.GetAssemblies().Where{$_.location -match ('{0}$' -f [regex]::Escape($assemblyFileName))} |
        Select-Object -First 1

    if ($loadedAssembly)
    {
        Write-Verbose -Message "Assembly already loaded: $_"
    }
    else
    {
        if (Test-Path -Path $assemblyPath)
        {
            Write-Verbose -Message "Loading assembly: $assemblyPath"
            $loadedAssembly = [System.Reflection.Assembly]::LoadFrom($assemblyPath)
        }
        else
        {
            Write-Error -Message "Assembly not found: $assemblyPath"
        }
    }

    if (
        $IsCoreCLR -and
        $assemblyFileName -eq 'SQLitePCLRaw.provider.e_sqlite3.dll' -and
        $loadedAssembly
    )
    {
        [PSSqlite.NativeLibraryResolver]::Register($loadedAssembly, $nativeLibraryHandle)
    }
}
