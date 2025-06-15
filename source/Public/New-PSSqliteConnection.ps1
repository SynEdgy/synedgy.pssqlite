using namespace Microsoft.Data.Sqlite
function New-PSSqliteConnection
{
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
