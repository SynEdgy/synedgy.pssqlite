function Close-PSSqliteConnection
{
    <#
    .SYNOPSIS
        Closes the SQLite connections.

    .DESCRIPTION
        This function closes all SQLite connection pools, effectively closing all active connections to the SQLite database.

    .EXAMPLE
        Close-PSSqliteConnection
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param
    (
        # no parameter required
    )

    [Microsoft.Data.Sqlite.SqliteConnection]::ClearAllPools()
}
