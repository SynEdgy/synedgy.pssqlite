using namespace System.Collections
using namespace System.Collections.Generic

function Get-PSSqliteDBConfigFile
{
    <#
    .SYNOPSIS
    Retrieves the path to the SQLite database configuration file for the current module.

    .DESCRIPTION
    This function constructs the expected path to the SQLite database configuration file
    based on the module's folder structure.
    It looks for a file named '{ModuleName}.PSSqliteConfig.yml' in the 'config' folder of the calling module.

    .PARAMETER ParentModuleBaseFolder
    The base folder of the parent module, typically the module that calls this function.

    .PARAMETER ConfigFolder
    The folder where the configuration file is located.
    By default, it looks for a folder named 'config' in the parent module's base folder.

    .PARAMETER ConfigFileName
    The name of the configuration file.
    By default, it looks for a file named '{ModuleName}.PSSqliteConfig.yml'.
    If the module name cannot be determined, it defaults to '*', which matches any file with the specified pattern.

    .EXAMPLE
    $configFile = Get-PSSqliteDBConfigFile -ParentModuleBaseFolder 'C:\Path\To\Module'
    Retrieves the SQLite database configuration file path from the specified parent module base folder.

    .NOTES
    General notes
    #>
    [cmdletBinding()]
    [OutputType([string])]
    param
    (
        [Parameter(DontShow)]
        [string]
        # The base folder of the parent module, typically the module that calls this function.
        $ParentModuleBaseFolder = $(
            Write-Debug -Message 'Determining the parent module base folder...'
            #Write-Debug -Message ('?? {0}' -f (((Get-PSCallStack)[0]).InvocationInfo.MyCommand.Module.ModuleBase | ConvertTo-JSON -depth 3))
            # Get the base folder of the parent module.
            # This is determined by the module that calls this function.
            if ($moduleBase = (((Get-PSCallStack)[0]).InvocationInfo.MyCommand.Module.ModuleBase))
            {
                $moduleBase
            }
            else
            {
                '.'
            }
        ),

        [Parameter()]
        # Retrieves the file path for the Sqlite database configuration.
        # By default, it looks for a file named '{ModuleName}.PSSqliteConfig.yml' in the 'config' folder of the calling module.
        [string]
        $ConfigFolder = (Join-Path -Path $ParentModuleBaseFolder -ChildPath 'config'),

        [Parameter()]
        [string]
        $ConfigFileName = $(
            if ($moduleName = (((Get-PSCallStack)[0]).InvocationInfo.MyCommand.Module.Name))
            {
                '{0}.PSSqliteConfig.y*ml' -f $moduleName
            }
            else
            {
                '{0}.PSSqliteConfig.y*ml' -f '*'
            }
        )
    )

    Write-Verbose -Message ('Retrieving SQLite configuration file from folder {0} ({1})' -f $ConfigFolder, $ParentModuleBaseFolder)
    $ConfigFolder = Get-PSSqliteAbsolutePath -Path $ConfigFolder

    Write-Verbose -Message ('Absolute path for config folder {0} ({1})' -f $ConfigFolder, $ParentModuleBaseFolder)
    $ConfigFile = Join-Path -Path $ConfigFolder -ChildPath $ConfigFileName
    Write-Verbose -Message ('Searching for configuration file like {0}' -f $ConfigFile)
    $ConfigFile = (Get-ChildItem -Path $ConfigFile -ErrorAction Stop).FullName

    if (-not (Test-Path -Path $ConfigFile))
    {
        Write-Error -Message ('Configuration file not found: {0}' -f $ConfigFile)
    }

    return $ConfigFile
}
