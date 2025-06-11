$assembliesToLoad = @(
    # This list should be loaded in the order they are listed
    'SQLitePCLRaw.core.dll',
    'SQLitePCLRaw.batteries_v2.dll',
    'Microsoft.Data.Sqlite.dll'
)

# Add Native assemblies to process $Env:PATH
$libPath = Join-Path -Path $PSScriptRoot -ChildPath "lib"

$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToLower()
$os = if ($IsWindows) { 'win' }
      elseif ($IsMacOS) { 'osx' }
      elseif ($IsLinux) { 'linux' }
      else { throw "Unsupported OS" }

$expectedRID - '{0}-{1}' -f $os, $arch
# Add the native assemblies to the PATH
$osRuntimePath = Join-Path -Path $runtimesPath -ChildPath $expectedRID
$nativePath = Join-Path -Path $osRuntimePath -ChildPath 'native'
if (-not (Test-Path -Path $nativePath))
{
    Write-Error -Message "Native path not found: $nativePath"
    return
}

# Add the native path to the environment PATH variable
$env:PATH = @($nativePath,$env:PATH) -join [io.path]::PathSeparator
# Load the managed assemblies in order
$IsCoreCLR = $PSVersionTable.PSEdition -eq 'Core'
$framework = if ($IsCoreCLR) { 'netstandard2.0' } else { 'netstandard2.0' } # or 'net461'
$managedAssembliesFolder = Join-Path -Path $libPath -ChildPath $framework

$assembliesToLoad | ForEach-Object {
    $assemblyPath = Join-Path -Path $managedAssembliesFolder -ChildPath $_
    if (Test-Path -Path $assemblyPath)
    {
        [System.Reflection.Assembly]::LoadFrom($assemblyPath) | Out-Null
    }
    else
    {
        Write-Error -Message "Assembly not found: $assemblyPath"
    }
}
