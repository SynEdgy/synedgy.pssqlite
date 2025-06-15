function Initialize-PSSqliteDatabase
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        # Path to the database configuration file
        [string]
        $DatabaseConfigPath,

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
    if (-not (Test-Path -Path $DatabaseConfigPath -PathType Leaf -IsValid))
    {
        throw "The specified database configuration file does not exist: $DatabaseConfigPath"
    }
    else
    {
        $databaseConfig = Get-PSSqliteDBConfig -ConfigFile $DatabaseConfigPath
    }

    Write-Verbose -Message ('Loaded database configuration from {0}.' -f $DatabaseConfigPath)
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
    if (-not $databaseConfig.databaseExists())
    {
        Write-Verbose -Message 'No existing database found. Creating a new database.'
        $databaseConfig.createDatabase()
    }
    elseif ($databaseConfig.databaseExists())
    {
        Write-Verbose -Message 'Existing database found. Checking for updates.'

        $compareResult = Compare-PSSqliteDBVersion -ExpectedVersion $databaseConfig.DBVersion -DatabaseConfig $databaseConfig

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
                $databaseConfig.updateDBSchema()
            }
            else
            {
                Write-Verbose -Message 'Database is already up-to-date. No changes made.'
            }
        }

        'CREATE'
        {
            Write-Verbose -Message 'Migration mode is set to CREATE. Creating a new database if it does not exist.'
            if ($shouldUpdateDB -and -not $databaseConfig.databaseExists())
            {
                Write-Verbose -Message 'Creating a new database schema.'
                $databaseConfig.createDatabase()
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
                $databaseConfig.removeDatabase()
                $databaseConfig.createDatabase()
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
