using namespace Microsoft.Data.Sqlite
function New-PSSqliteConnection
{
    [CmdletBinding()]
    [OutputType([Microsoft.Data.Sqlite.SqliteConnection])]
    param
    (
        [Parameter()]
        [string]
        $ConnectionString = 'Data Source=:memory:;Cache=Shared;'
    )

    try
    {
        $connection = [SqliteConnection]::new($ConnectionString)
        return $connection
    }
    catch
    {
        Write-Error "Failed to create SQLite connection: $_"
    }
}
