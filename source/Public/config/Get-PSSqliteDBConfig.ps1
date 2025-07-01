function Get-PSSqliteDBConfig
{
    <#
    .SYNOPSIS
    Retrieves the SQLiteDBConfig object from a specified configuration file.

    .DESCRIPTION
    This function loads the SQLiteDBConfig from the specified file path.
    The file should contain the necessary configuration details for connecting to a SQLite database.

    .PARAMETER Path
    The path to the configuration file.
    This file should contain the SQLiteDBConfig in a format that can be deserialized into a SQLiteDBConfig object.
    If the file does not exist, an exception will be thrown.

    .EXAMPLE
    $config = Get-PSSqliteDBConfig -Path 'C:\path\to\config.json'
    Loads the SQLiteDBConfig from the specified JSON file.

    .NOTES
    This function is part of a module that provides configuration management for SQLite databases.
    It requires the SQLiteDBConfig class to be defined and available in the module.
    The next step is to Initialize-PSSqliteDatabase with the loaded configuration to make sure the schema is applied.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]
        [Alias('ConfigFile')]
        $Path
    )

    $Path = Get-PSSqliteAbsolutePath -Path $Path

    if (-not (Test-Path -Path $Path))
    {
        throw [System.IO.FileNotFoundException]::new("Configuration file not found: $Path")
    }

    Write-Verbose -Message ('Loading SQLiteDBConfig from {0}' -f $Path)
    return [SQLiteDBConfig]::new($Path)
}
