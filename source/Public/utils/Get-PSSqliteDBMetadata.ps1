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

    .PARAMETER SqliteConnection
        Connection to query.
    .PARAMETER MetadataKey
        Metadata keys to retrieve, or * for all keys.
    .PARAMETER KeepAlive
        Leave the connection open.
    .PARAMETER SqliteTransaction
        Caller-owned transaction on the supplied connection; keeps it open.
    #>

    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [Microsoft.Data.Sqlite.SqliteConnection]
        $SqliteConnection,

        [Parameter()]
        [string[]]
        $MetadataKey = @('*'),

        [Parameter()]
        [switch]
        $KeepAlive,

        [Parameter()]
        [Microsoft.Data.Sqlite.SqliteTransaction]
        $SqliteTransaction
    )

    try
    {
        $queryParameters = @{
            SqliteConnection = $SqliteConnection
            SqliteTransaction = $SqliteTransaction
            KeepAlive = $true
            ErrorAction = 'Stop'
        }

        $metadataPresent = Invoke-PSSqliteQuery @queryParameters -CommandText 'SELECT name from sqlite_schema WHERE name = @name COLLATE NOCASE' -Parameters @{name = '_metadata'}

        if ($metadataPresent)
        {
            if ($MetadataKey -contains '*')
            {
                $query = 'SELECT key, value from _metadata;'
                $metadataRows = @(Invoke-PSSqliteQuery @queryParameters -CommandText $query -As OrderedDictionary)
            }
            else
            {
                $sqlParameters = @{}

                $keyPlaceholders = for ($index = 0; $index -lt $MetadataKey.Count; $index++)
                {
                    $parameterName = 'MetadataKey{0}' -f $index
                    $sqlParameters[$parameterName] = $MetadataKey[$index]
                    '@{0}' -f $parameterName
                }

                $query = 'SELECT key, value from _metadata WHERE key IN ({0});' -f ($keyPlaceholders -join ', ')
                $metadataRows = @(Invoke-PSSqliteQuery @queryParameters -CommandText $query -Parameters $sqlParameters -As OrderedDictionary)
            }

            if ($metadataRows.Count -gt 0)
            {
                $metadata = [ordered]@{}

                foreach ($row in $metadataRows)
                {
                    $metadata[$row['key']] = $row['value']
                }
            }
        }

        return $metadata
    }
    catch
    {
        Write-Error -Message "Failed to get SQLite DB metadata: $_"
    }
    finally
    {
        if (-not $KeepAlive -and -not $SqliteTransaction -and $SqliteConnection.State -eq 'Open')
        {
            $SqliteConnection.Close()
        }
    }
}
