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
            if (-not [string]::IsNullOrEmpty($configFileObject.ConnectionString))
            {
                $this.ConnectionString = $configFileObject.ConnectionString
                # DatabasePath and DatabaseFile are ignored in this case
            }
            else
            {
                $this.DatabasePath = $configFileObject.DatabasePath
                $this.DatabaseFile = $configFileObject.DatabaseFile
                $this.ConnectionString = 'Data Source={0};' -f (Join-Path -Path $this.DatabasePath -ChildPath $this.DatabaseFile)
            }
        }
    }

    static [SQLiteDBConfig] Load([string]$StringInfo)
    {
        return [SQLiteDBConfig]::new($StringInfo)
    }
}
