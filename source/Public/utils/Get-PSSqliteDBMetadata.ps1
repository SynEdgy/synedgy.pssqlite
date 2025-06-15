function Get-PSSqliteDBMetadata
{
    <#
    .SYNOPSIS
        Gets the database's custom metadata (such as database schema version, which is not the engine/sqlite version).

    .DESCRIPTION
        This function retrieves the version of the SQLite database schema from the _metadata table that we use by convention.
        We store the schema (yaml) version in the _metadata table, so we can track changes to the database schema over time.

    .EXAMPLE
        Get-SQLiteDBVersion -MetadataKey Version
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [Microsoft.Data.Sqlite.SqliteConnection]
        $SqliteConnection,

        [Parameter()]
        [string[]]
        $MetadataKey = @('*')
    )

    try
    {
        $metadataPresent = Invoke-PSSqliteQuery -SqliteConnection $SqliteConnection -CommandText 'SELECT name from sqlite_schema WHERE name = @name COLLATE NOCASE' -Parameters @{name = '_metadata'}
        if ($metadataPresent)
        {
            if ($MetadataKey -contains '*')
            {
                $query = 'SELECT key, value from _metadata;'
                $metadata = Invoke-PSSqliteQuery -SqliteConnection $SqliteConnection -CommandText $query -As OrderedDictionary
            }
            else
            {
                # If specific keys are requested, format the query accordingly
                $query = 'SELECT key, value from _metadata WHERE key IN (''{0}'');' -f ($MetadataKey -join "','")
                $metadata = Invoke-PSSqliteQuery -SqliteConnection $SqliteConnection -CommandText $query -As OrderedDictionary
            }
        }

        return $metadata
    }
    catch
    {
        Write-Error -Message "Failed to get SQLite DB metadata: $_"
    }
}
