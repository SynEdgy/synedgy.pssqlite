class SQLiteDBConfig
{
    [string] $DatabasePath
    [string] $DatabaseFile
    [string] $ConnectionString
    [SqliteDBSchema] $Schema


    SQLiteDBConfig()
    {
        # Default constructor
    }

    SQLiteDBConfig([string]$DatabasePath, [string]$DatabaseFile)
    {
        $this.DatabasePath = $DatabasePath
        $this.DatabaseFile = $DatabaseFile
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

    static [SQLiteDBConfig] Load([string]$StringInfo)
    {
        return [SQLiteDBConfig]::new($StringInfo)
    }

    hidden SetObjectProperties([System.Collections.IDictionary]$Definition)
    {
        if ($Definition.Keys -contains 'DatabasePath')
        {
            $this.DatabasePath = $Definition['DatabasePath']
        }

        if ($Definition.Keys -contains 'DatabaseFile')
        {
            $this.DatabaseFile = $Definition['DatabaseFile']
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

        if ($Definition.Keys -contains 'Schema')
        {
            $this.Schema = [SqliteDBSchema]::new($Definition['Schema'])
        }
    }
}
