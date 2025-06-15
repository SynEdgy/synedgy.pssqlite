function Get-PSSqliteDBConfig
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ConfigFile
    )

    $ConfigFile = Get-PSSqliteAbsolutePath -Path $ConfigFile

    if (-not (Test-Path -Path $ConfigFile))
    {
        throw [System.IO.FileNotFoundException]::new("Configuration file not found: $ConfigFile")
    }

    return [SQLiteDBConfig]::new($ConfigFile)
}
