param (

)

# task nuget_restore,dotnet_nuget_restore

task dotnet_nuget_restore {
    # dotnet restore .\synedgy.pssqlite.csproj --packages output/nuget/
    $nugetPackages = Get-ChildItem -Path output/nuget/ -Directory
    $sourceLibFolder = '.\source\lib\'
    $sourceNetStd2Folder = Join-Path -Path $sourceLibFolder -ChildPath 'netstandard2.0'
    $sourceRuntimesFolder = Join-Path -Path $sourceLibFolder -ChildPath 'runtimes'

    if (-not (Test-Path -Path $sourceLibFolder))
    {
        $null = New-Item -ItemType Directory -Path $sourceLibFolder -Force
    }

    if (-not (Test-Path -Path $sourceNetStd2Folder))
    {
        $null = New-Item -ItemType Directory -Path $sourceNetStd2Folder -Force
    }

    if (-not (Test-Path -Path $sourceRuntimesFolder))
    {
        $null = New-Item -ItemType Directory -Path $sourceRuntimesFolder -Force
    }

    $nugetPackages.ForEach{
        $package = $_
        $netStdFolder = Join-Path -Path $package.FullName -ChildPath '*/lib/netstandard2.0/'
        $netStdVersionFolder = Get-Item -Path $netStdFolder -ErrorAction SilentlyContinue
        $runtimesFolder = Join-Path -Path $package.FullName -ChildPath '*/runtimes/'
        $runtimesVersionFolder = Get-Item -Path $runtimesFolder -ErrorAction SilentlyContinue
        Write-Build cyan ('-- {0}' -f $package.BaseName)
        if ($netStdVersionFolder)
        {
            Get-ChildItem -Path $netStdVersionFolder -ErrorAction SilentlyContinue | Foreach-Object -Process {
                if ($_.BaseName -ne '_')
                {
                    Write-Build Cyan ('    > {0}' -f ($_.FullName))
                    Copy-Item -Path $_.FullName -Destination '.\source\lib\netstandard2.0\' -Force
                }
                else
                {
                    Write-Build Yellow $_
                }
            }
        }

        if ($runtimesVersionFolder)
        {
            $excludedRIDs = @(
                'android-arm'
                'android-arm64'
                'android-x64'
                'android-x86'
                'browser-wasm'
                'ios-arm'
                'ios-arm64'
                'iossimulator-arm64'
                'iossimulator-x64'
                'iossimulator-x86'
                'uap10.0'
                'maccatalyst-x64'
                'maccatalyst-arm64'
                'linux-mips64'
                'linux-musl-riscv64'
                'linux-musl-s390x'
                'linux-musl-x64'
                'linux-musl-arm64'
                'linux-musl-arm'
                'linux-musl-x86'
                'linux-musl-x86_64'
                'linux-musl-armv7'
                'linux-musl-armv6'
                'linux-musl-armv5'
                'linux-musl-armv8'
                'linux-musl-armv7l'
                'linux-musl-armv8l'
                'linux-musl-armv6l'
                'linux-s390x'
                'linux-armel'
                'linux-ppc64le'
                'linux-riscv64'
                'win10-arm'
                'win10-arm64'
                'win10-x64'
                'win10-x86'
            )

            Get-ChildItem -Path $runtimesVersionFolder -ErrorAction SilentlyContinue | Foreach-Object -Process {
                if ($_.BaseName -notin $excludedRIDs)
                {
                    Write-Build Cyan ('    > {0}' -f ($_.BaseName))
                    Copy-Item -Path $_.FullName -Destination '.\source\lib\runtimes\' -Force -Recurse
                }
            }
        }
    }
}
