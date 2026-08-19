
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
        OVERWRITE: Back up the database and its data, recreate the database file, and
        restore compatible data into the new schema.

        .PARAMETER Force
        Forces the initialization process to use OVERWRITE mode even when the schema
        version is already current.

        .PARAMETER NoPreserveData
        Skips the database backup, JSON data export, and compatible-row restore during
        an OVERWRITE migration. The existing database data will be permanently removed.

        .PARAMETER DataBackupPath
        Directory for the complete database backup and JSON data dump. When omitted,
        a timestamped directory is created next to the database file.

        .EXAMPLE
        Initialize-PSSqliteDatabase -DatabaseConfig $config -MigrationMode OVERWRITE

        Backs up the database, recreates the schema, and restores compatible data.

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
        $Force,

        [Parameter()]
        [switch]
        $NoPreserveData,

        [Parameter()]
        [string]
        $DataBackupPath
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

        $compareResult = Compare-PSSqliteDBVersion -ExpectedVersion $DatabaseConfig.Version -DatabaseConfig $DatabaseConfig

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
                if (-not $NoPreserveData -and $DatabaseConfig.databaseExists())
                {
                    if (-not $DataBackupPath)
                    {
                        $backupDirectoryName = '{0}.data-{1}' -f $DatabaseConfig.DatabaseFile, (Get-Date -Format 'yyyyMMdd-HHmmss')
                        $DataBackupPath = Join-Path -Path $DatabaseConfig.DatabasePath -ChildPath $backupDirectoryName
                    }

                    $manifestPath = Join-Path -Path $DataBackupPath -ChildPath '_manifest.json'
                    if (Test-Path -Path $manifestPath -PathType Leaf)
                    {
                        throw [System.IO.IOException]::new(
                            "A SQLite migration backup already exists at '$DataBackupPath'. Choose another DataBackupPath."
                        )
                    }

                    if ($DatabaseConfig.ConnectionString -notmatch ':memory:')
                    {
                        $null = New-Item -Path $DataBackupPath -ItemType Directory -Force
                        $databaseFileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($DatabaseConfig.DatabaseFile)
                        $databaseBackupTimestamp = Get-Date -Format 'yyyy-MM-dd_HH.mm.ss'
                        $databaseBackupFile = '{0}_{1}.bak.db' -f $databaseFileBaseName, $databaseBackupTimestamp
                        $databaseBackupPath = Join-Path -Path $DataBackupPath -ChildPath $databaseBackupFile
                        $sourceConnection = $null
                        $backupConnection = $null

                        try
                        {
                            $sourceConnection = New-PSSqliteConnection -ConnectionString $DatabaseConfig.ConnectionString
                            $backupConnection = New-PSSqliteConnection -DatabasePath $DataBackupPath -DatabaseFile $databaseBackupFile
                            $sourceConnection.Open()
                            $backupConnection.Open()
                            $sourceConnection.BackupDatabase($backupConnection)
                        }
                        finally
                        {
                            if ($sourceConnection)
                            {
                                $sourceConnection.Dispose()
                            }

                            if ($backupConnection)
                            {
                                $backupConnection.Dispose()
                            }

                            Close-PSSqliteConnection
                        }

                        Write-Verbose -Message ("Created complete database backup at '{0}'." -f $databaseBackupPath)
                    }

                    $null = Export-PSSqliteData -SqliteDBConfig $DatabaseConfig -Path $DataBackupPath -ErrorAction Stop
                }

                Close-PSSqliteConnection
                $DatabaseConfig.removeDatabase()
                $DatabaseConfig.createDatabase()

                if (-not $NoPreserveData -and $DataBackupPath)
                {
                    $restoreResults = @(Import-PSSqliteData -SqliteDBConfig $DatabaseConfig -Path $DataBackupPath -ErrorAction Continue)
                    $failedRows = [int](($restoreResults | Measure-Object -Property Failed -Sum).Sum)
                    if ($failedRows -gt 0)
                    {
                        throw [System.InvalidOperationException]::new(
                            "The database schema was recreated, but $failedRows row(s) could not be restored. The data dump remains at '$DataBackupPath'."
                        )
                    }
                }
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
