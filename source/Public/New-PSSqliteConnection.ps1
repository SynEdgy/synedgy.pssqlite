using namespace Microsoft.Data.Sqlite
function New-PSSqliteConnection
{
    <#
    .SYNOPSIS
    Creates a new SQLite connection.

    .DESCRIPTION
    This function creates a new SQLite connection based on the provided parameters.

    .PARAMETER ConnectionString
    The connection string to use for the SQLite connection.
    If not specified, it defaults to an in-memory database with shared cache.
    If using a :memory: database, the KeepAlive parameter must be specified to keep the connection open.

    .PARAMETER DatabasePath
    The file system path to the directory containing the SQLite database file.

    .PARAMETER DatabaseFile
    The name of the SQLite database file.

    .EXAMPLE
    $connection = New-PSSqliteConnection -ConnectionString 'Data Source=C:\path\to\database.db;'
    Creates a new SQLite connection using the specified connection string.

    .NOTES
    This function is part of a module that provides CRUD operations for SQLite databases.
    #>
    [CmdletBinding(DefaultParameterSetName = 'byConnectionString')]
    [OutputType([Microsoft.Data.Sqlite.SqliteConnection])]
    param
    (
        [Parameter(ParameterSetName = 'byConnectionString')]
        [string]
        $ConnectionString = 'Data Source=:memory:;Cache=Shared;',

        [Parameter(ParameterSetName = 'byDatabasePath')]
        [string]
        # Path to the SQLite database file. If not specified but DatabaseFile is provided, it assumes working directory.
        $DatabasePath = (Get-Location).Path,

        [Parameter(ParameterSetName = 'byDatabasePath', Mandatory = $true)]
        [string]
        $DatabaseFile
    )

    try
    {
        switch ($PSCmdlet.ParameterSetName)
        {
            'byConnectionString'
            {
                # Use the provided connection string
                $ConnectionString = $ConnectionString
            }

            'byDatabasePath'
            {
                if (-not (Test-Path -Path $DatabasePath))
                {
                    Write-Verbose "Database path '$DatabasePath' does not exist. Creating it."
                    $null = New-Item -Path $DatabasePath -ItemType Directory -Force
                }

                # Construct the connection string from the database path
                $dataSource = Join-Path -Path $DatabasePath -ChildPath $DatabaseFile
                if (-not (Test-Path -Path $dataSource))
                {
                    Write-Verbose "Database file '$dataSource' does not exist. Creating a new one."
                    $null = New-Item -Path $dataSource -ItemType File -Force
                }

                $ConnectionString = 'Data Source={0};' -f $dataSource
            }
        }

        $connection = [SqliteConnection]::new($ConnectionString)
        return $connection
    }
    catch
    {
        Write-Error "Failed to create SQLite connection: $_"
    }
}
