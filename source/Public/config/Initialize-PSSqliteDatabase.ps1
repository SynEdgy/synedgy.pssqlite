
function Initialize-PSSqliteDatabase
{
    <#
        .SYNOPSIS
        Initializes a SQLite database based on the provided configuration.

        .DESCRIPTION
        This function initializes a SQLite database using the specified configuration file or object.
        It supports different migration modes to handle existing databases.

        .PARAMETER Path
        Path to the database configuration file.

        .PARAMETER DatabaseConfig
        SQLiteDBConfig object containing the database configuration.

        .PARAMETER MigrationMode
        Migration mode for the database initialization. Options are INCREMENTAL, CREATE, or OVERWRITE.
        INCREMENTAL: Assume the database already exists and only apply changes if the registered version is lower than the expected version.
        CREATE: Only create a new database if it doesn't exist already.
        OVERWRITE: Remove the db file and create a new one, (!!!) dropping all data (!!!).

        .PARAMETER Force
        If set, forces the initialization process, overwriting existing configurations, and replacing the database file if it exists.
        ALL DATA WILL BE LOST.

    #>
    [CmdletBinding(DefaultParameterSetName = 'byPath')]
    [OutputType([void])]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'byPath')]
        # Path to the database configuration file
        [string]
        [Alias('DatabaseConfigPath')]
        $Path,

        [Parameter(Mandatory = $true, ParameterSetName = 'byConfig')]
        # SQLiteDBConfig object containing the database configuration
        [Alias('SqliteDBConfig')]
        [SQLiteDBConfig]
        $DatabaseConfig,

        [Parameter()]
        [DBMigrationMode]
        # Migration mode for the database initialization
        # INCREMENTAL: Assume the database already exists and only apply changes "IF NOT EXISTS"
        # CREATE: Only create a new database if it doesn't exist, dropping any existing tables
        # OVERWRITE: Remove the db file and create a new one
        $MigrationMode = [DBMigrationMode]::INCREMENTAL,

        [Parameter()]
        [switch]
        $Force
    )

    # Load the SQLiteDBConfig
    switch ($PSCmdlet.ParameterSetName)
    {
        'byPath'
        {
            if (-not (Test-Path -Path $Path -PathType Leaf -IsValid))
            {
                throw "The specified database configuration file does not exist: $Path"
            }
            else
            {
                $DatabaseConfig = Get-PSSqliteDBConfig -ConfigFile $Path
            }
        }

        'byConfig'
        {
            Write-Verbose -Message 'Using provided SQLiteDBConfig object.'
            if (-not $DatabaseConfig -or $null -ne $DatabaseConfig.Schema.ValidateDefinition())
            {
                throw "Invalid SQLiteDBConfig object provided."
            }
        }
    }

    Write-Verbose -Message ('Loaded database configuration from {0}.' -f $Path)
    if ($Force.IsPresent)
    {
        Write-Verbose -Message 'Force flag is set. Overwriting the database configuration.'
        $MigrationMode = [DBMigrationMode]::OVERWRITE
    }

    # Initialize the database
    #  Check if the db exist (or it's a :memory: database which we assume always exists),\
    #  Compare the version of the config file with the database version in _metadata table
    #  init the db depending of the MigrationMode and comparison direction
    [bool] $shouldUpdateDB = $false
    if (-not $DatabaseConfig.databaseExists())
    {
        Write-Verbose -Message 'No existing database found. Creating a new database.'
        $DatabaseConfig.createDatabase()
    }
    elseif ($DatabaseConfig.databaseExists())
    {
        Write-Verbose -Message 'Existing database found. Checking for updates.'

        $compareResult = Compare-PSSqliteDBVersion -ExpectedVersion $DatabaseConfig.DBVersion -DatabaseConfig $DatabaseConfig

        if ($compareResult.direction -eq '==')
        {
            Write-Verbose -Message ('Database is already at the expected version: {0}' -f $compareResult.CurrentVersion)
            $shouldUpdateDB = $false
        }
        elseif ($compareResult.direction -eq '>')
        {
            Write-Verbose -Message ('Database version is newer than expected: {0} > {1}' -f $compareResult.CurrentVersion, $compareResult.ExpectedVersion)
            $shouldUpdateDB = $false
        }
        elseif ($compareResult.direction -eq '<')
        {
            Write-Verbose -Message ('Database version is outdated: {0} != {1}' -f $compareResult.CurrentVersion, $compareResult.ExpectedVersion)
            $shouldUpdateDB = $true
        }
        elseif ($compareResult.direction -eq '!=')
        {
            Write-Verbose -Message ('Database version is different: {0} != {1}' -f $compareResult.CurrentVersion, $compareResult.ExpectedVersion)
            $shouldUpdateDB = $true
        }
        else
        {
            Write-Verbose -Message 'Unexpected comparison result. Assuming update is required.'
            $shouldUpdateDB = $true
        }
    }
    else
    {
        Write-Verbose -Message 'No existing database found. Initializing a new database.'
    }

    Write-Verbose -Message ('Migration mode is set to {0}. Should update DB: {1}' -f $MigrationMode, $shouldUpdateDB)

    switch ($MigrationMode)
    {
        'INCREMENTAL'
        {
            Write-Verbose -Message 'Migration mode is set to INCREMENTAL. Applying changes if necessary.'
            if ($shouldUpdateDB)
            {
                Write-Verbose -Message 'Updating the database schema to the latest version.'
                $DatabaseConfig.updateDBSchema()
            }
            else
            {
                Write-Verbose -Message 'Database is already up-to-date. No changes made.'
            }
        }

        'CREATE'
        {
            Write-Verbose -Message 'Migration mode is set to CREATE. Creating a new database if it does not exist.'
            if ($shouldUpdateDB -and -not $DatabaseConfig.databaseExists())
            {
                Write-Verbose -Message 'Creating a new database schema.'
                $DatabaseConfig.createDatabase()
            }
            else
            {
                Write-Verbose -Message 'Database already exists. No changes made. (should Update: {0}, MigrationMode: {1})' -f $shouldUpdateDB, $MigrationMode
            }
        }

        'OVERWRITE'
        {
            if ($Force.IsPresent -eq $true -or $shouldUpdateDB -eq $true)
            {
                Write-Verbose -Message 'Migration mode is set to OVERWRITE. Removing existing database and creating a new one.'
                $DatabaseConfig.removeDatabase()
                $DatabaseConfig.createDatabase()
            }
            else # if ($Force.IsPresent -eq $false -and $shouldUpdateDB -eq $false)
            {
                Write-Verbose -Message 'Migration mode is set to OVERWRITE, but the Force flag is not set and no changes are required. No action taken.'
            }
        }

        default
        {
            throw "Unsupported migration mode: $MigrationMode"
        }
    }
}
