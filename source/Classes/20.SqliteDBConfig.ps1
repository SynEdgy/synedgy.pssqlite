class SQLiteDBConfig
{
    hidden [string] $ConfigurationFile
    [string] $DatabasePath
    [string] $DatabaseFile
    [string] $ConnectionString
    [string] $Version = '0'
    [SqliteDBSchema] $Schema


    SQLiteDBConfig()
    {
        # Default constructor
    }

    SQLiteDBConfig([string]$DatabasePath, [string]$DatabaseFile)
    {
        $this.DatabasePath = Get-PSSqliteAbsolutePath -Path (Get-ExpandedString -String $DatabasePath)
        $this.DatabaseFile = Get-ExpandedString -String $DatabaseFile
        $this.ConnectionString = 'Data Source={0};' -f (Join-Path -Path $DatabasePath -ChildPath $DatabaseFile)
    }

    SQLiteDBConfig([string]$StringInfo)
    {
        if (-not (Test-Path -Path $StringInfo -PathType Leaf -IsValid))
        {
            # Test that the string is a valid connection string
            if ($StringInfo -notmatch '^Data Source=.*$')
            {
                throw "Invalid SQLite connection string format: $StringInfo"
            }
            else
            {
                $this.ConnectionString = $StringInfo
                return
            }
        }
        else
        {
            $configFileObject = Get-Content -Path $StringInfo | ConvertFrom-Yaml -Ordered
            $this.SetObjectProperties($configFileObject)
        }
    }

    SQLiteDBConfig ([System.Collections.IDictionary]$Definition)
    {
        $this.SetObjectProperties($Definition)
    }

    static [SQLiteDBConfig] Load([string]$ConfigFile)
    {
        $ConfigFile = Get-PSSqliteAbsolutePath -Path $ConfigFile
        return [SQLiteDBConfig]::new($ConfigFile)
    }

    hidden SetObjectProperties([System.Collections.IDictionary]$Definition)
    {
        if ($Definition.Keys -contains 'DatabasePath')
        {
            $dbPath = Get-ExpandedString -String $Definition['DatabasePath']
            $this.DatabasePath = Get-PSSqliteAbsolutePath -Path $dbPath
        }

        if ($Definition.Keys -contains 'DatabaseFile')
        {
            $dbFile = Get-ExpandedString -String $Definition['DatabaseFile']
            $this.DatabaseFile = $dbFile
        }

        if ($Definition.Keys -contains 'ConnectionString')
        {
            $this.ConnectionString = $Definition['ConnectionString']
        }
        else
        {
            if ($this.DatabaseFile)
            {
                $this.ConnectionString = 'Data Source={0};' -f (Join-Path -Path $this.DatabasePath -ChildPath $this.DatabaseFile)
            }
            else
            {
                throw [System.ArgumentException]::new('DatabasePath and DatabaseFile must be set to construct a valid connection string.')
            }
        }

        if ($Definition.Keys -contains 'Version')
        {
            $this.Version = $Definition['Version']
        }

        if ($Definition.Keys -contains 'Schema')
        {
            $this.Schema = [SqliteDBSchema]::new($Definition['Schema'])
        }
    }

    [string] GetDatabaseSDL()
    {
        if (-not $this.Schema)
        {
            throw [System.InvalidOperationException]::new('Schema is not defined in the database configuration.')
        }

        return $this.Schema.GetSchemaSDL()
    }

    hidden [bool] databaseExists()
    {
        if ($this.ConnectionString -match ':memory:')
        {
            return $true
        }
        else
        {
            $dbFilePath = Join-Path -Path $this.DatabasePath -ChildPath $this.DatabaseFile
            return (Test-Path -Path $dbFilePath -PathType Leaf)
        }
    }

    hidden [void] removeDatabase()
    {
        if ($this.databaseExists() -and $this.ConnectionString -notmatch ':memory:')
        {
            $DatabasePathFolder = Get-PSSqliteAbsolutePath -Path $this.DatabasePath
            $dbFilePath = Join-Path -Path $DatabasePathFolder -ChildPath $this.DatabaseFile
            if (-not (Test-Path -Path $dbFilePath -PathType Leaf))
            {
                # can't find the file but $this.databaseExists() returned true
                Write-Warning -Message ('Database path does not exist: {0}.' -f $dbFilePath)
            }
            else
            {
                Write-Verbose -Message ('Removing existing database file at {0}' -f $dbFilePath)
                Remove-Item -Path $dbFilePath -Force -ErrorAction Stop
            }
        }
        else
        {
            Write-Verbose -Message 'No existing database file to remove.'
        }
    }

    hidden [void] updateDBSchema()
    {
        Invoke-PSSqliteSchemaSetup -DatabaseConfig $this -ErrorAction Stop
    }

    hidden [void] createDatabase()
    {
        Write-Verbose -Message 'Creating database...'
        $this.createDatabase($false, $false)
    }

    hidden [void] createDatabase([bool]$Force)
    {
        Write-Verbose -Message ('Creating database with Force={0}... (no schema update)' -f $Force)
        $this.createDatabase($Force, $true)
    }

    hidden [void] createDatabase([bool]$Force, [bool]$SkipSchemaUpdate)
    {
        if ($this.databaseExists() -and -not $Force)
        {
            throw [System.InvalidOperationException]::new('Database already exists. Use Force to overwrite.')
        }
        elseif ($this.databaseExists() -and $Force)
        {
            $this.removeDatabase()
        }
        else
        {
            if (-not (Test-Path -Path $this.DatabasePath -PathType Container))
            {
                Write-Verbose -Message ('Creating database path at {0}' -f $this.DatabasePath)
                $null = New-Item -Path $this.DatabasePath -ItemType Directory -Force
            }
        }

        if (-not $SkipSchemaUpdate)
        {
            $this.updateDBSchema()
        }
    }
}
