function Get-PSSqliteDBConfig
{
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
