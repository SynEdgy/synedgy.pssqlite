BeforeDiscovery {
    $projectPath = "$($PSScriptRoot)\..\.." | Convert-Path
    if (-not $ProjectName)
    {
        $ProjectName = Get-SamplerProjectName -BuildRoot $projectPath
    }

    Remove-Module -Name $ProjectName -Force -ErrorAction SilentlyContinue
    $null = Get-Module -Name $ProjectName -ListAvailable |
        Select-Object -First 1 |
        Import-Module -Force -ErrorAction Stop
}

BeforeAll {
    function New-ImportTestConfig
    {
        param
        (
            [Parameter(Mandatory = $true)]
            [string]
            $DatabaseFile,

            [Parameter()]
            [switch]
            $NewSchema
        )

        if ($NewSchema)
        {
            $schemaSpecificColumn = @"
        Category:
          Type: INTEGER
          DefaultValue: 42
"@
        }
        else
        {
            $schemaSpecificColumn = @"
        RemovedColumn:
          Type: TEXT
"@
        }

        $databasePath = Join-Path -Path $TestDrive -ChildPath 'db'
        $configPath = Join-Path -Path $TestDrive -ChildPath "$DatabaseFile.PSSqliteConfig.yml"
        $version = if ($NewSchema) { '2.0.0' } else { '1.0.0' }
        $null = New-Item -Path $databasePath -ItemType Directory -Force

        @"
DatabasePath: '$databasePath'
DatabaseFile: '$DatabaseFile'
Version: '$version'
Schema:
  Tables:
    Items:
      Columns:
        Id:
          Type: INTEGER
          PrimaryKey: true
          AllowNull: false
        Name:
          Type: TEXT
        Content:
          Type: BLOB
$schemaSpecificColumn
"@ | Set-Content -Path $configPath

        Get-PSSqliteDBConfig -Path $configPath
    }
}

Describe 'Import-PSSqliteData' {
    It 'Should restore common columns, blobs, nulls, and destination defaults' {
        $oldConfig = New-ImportTestConfig -DatabaseFile 'old.sqlite'
        Initialize-PSSqliteDatabase -DatabaseConfig $oldConfig -ErrorAction Stop
        $connection = New-PSSqliteConnection -ConnectionString $oldConfig.ConnectionString

        try
        {
            $connection.Open()
            $command = $connection.CreateCommand()
            $command.CommandText = 'INSERT INTO Items (Name, Content, RemovedColumn) VALUES (@name, @content, NULL);'
            $null = $command.Parameters.AddWithValue('@name', 'one')
            $null = $command.Parameters.AddWithValue('@content', [byte[]](10, 20, 30))
            $null = $command.ExecuteNonQuery()
        }
        finally
        {
            [Microsoft.Data.Sqlite.SqliteConnection]::ClearPool($connection)
            $connection.Dispose()
        }

        $dumpPath = Join-Path -Path $TestDrive -ChildPath 'dump'
        $null = Export-PSSqliteData -SqliteDBConfig $oldConfig -Path $dumpPath -ErrorAction Stop

        $newConfig = New-ImportTestConfig -DatabaseFile 'new.sqlite' -NewSchema
        Initialize-PSSqliteDatabase -DatabaseConfig $newConfig -ErrorAction Stop
        $result = @(Import-PSSqliteData -SqliteDBConfig $newConfig -Path $dumpPath -ErrorAction Stop)

        $result[0].Imported | Should -Be 1
        $row = @(Get-PSSqliteRow -SqliteDBConfig $newConfig -TableName 'Items' -ErrorAction Stop)[0]
        $row.Name | Should -Be 'one'
        $row.Category | Should -Be 42
        [Convert]::ToBase64String([byte[]]$row.Content) | Should -Be 'ChQe'
        $row.PSObject.Properties.Name | Should -Not -Contain 'RemovedColumn'
    }

    It 'Should restore parent tables before child tables when foreign keys are enabled' {
        $databasePath = Join-Path -Path $TestDrive -ChildPath 'foreign-key-db'
        $configPath = Join-Path -Path $TestDrive -ChildPath 'ForeignKeys.PSSqliteConfig.yml'
        $null = New-Item -Path $databasePath -ItemType Directory -Force

        @"
DatabasePath: '$databasePath'
DatabaseFile: 'foreign-keys.sqlite'
Version: '1.0.0'
Schema:
  Tables:
    Children:
      Columns:
        Id:
          Type: INTEGER
          PrimaryKey: true
          AllowNull: false
        ParentId:
          Type: INTEGER
    Parents:
      Columns:
        Id:
          Type: INTEGER
          PrimaryKey: true
          AllowNull: false
        Name:
          Type: TEXT
"@ | Set-Content -Path $configPath

        $config = Get-PSSqliteDBConfig -Path $configPath
        Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop
        $connection = New-PSSqliteConnection -ConnectionString $config.ConnectionString

        try
        {
            $connection.Open()
            $command = $connection.CreateCommand()
            $command.CommandText = @'
PRAGMA foreign_keys = OFF;
DROP TABLE Children;
CREATE TABLE Children (
    Id INTEGER PRIMARY KEY,
    ParentId INTEGER NOT NULL,
    FOREIGN KEY (ParentId) REFERENCES Parents(Id)
);
INSERT INTO Parents (Id, Name) VALUES (1, 'Parent');
INSERT INTO Children (Id, ParentId) VALUES (1, 1);
'@
            $null = $command.ExecuteNonQuery()
        }
        finally
        {
            [Microsoft.Data.Sqlite.SqliteConnection]::ClearPool($connection)
            $connection.Dispose()
        }

        $dumpPath = Join-Path -Path $TestDrive -ChildPath 'foreign-key-dump'
        $null = Export-PSSqliteData -SqliteDBConfig $config -Path $dumpPath -ErrorAction Stop

        Close-PSSqliteConnection
        Remove-Item -Path (Join-Path -Path $databasePath -ChildPath 'foreign-keys.sqlite') -Force
        Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop
        $connection = New-PSSqliteConnection -ConnectionString $config.ConnectionString

        try
        {
            $connection.Open()
            $command = $connection.CreateCommand()
            $command.CommandText = @'
PRAGMA foreign_keys = OFF;
DROP TABLE Children;
CREATE TABLE Children (
    Id INTEGER PRIMARY KEY,
    ParentId INTEGER NOT NULL,
    FOREIGN KEY (ParentId) REFERENCES Parents(Id)
);
PRAGMA foreign_keys = ON;
'@
            $null = $command.ExecuteNonQuery()

            $results = @(Import-PSSqliteData -SqliteDBConfig $config -Path $dumpPath -SqliteConnection $connection -ErrorAction Stop)

            $results[0].TableName | Should -Be 'Parents'
            $results[1].TableName | Should -Be 'Children'

            $command.CommandText = 'PRAGMA foreign_key_check;'
            $reader = $command.ExecuteReader()
            try
            {
                $reader.Read() | Should -BeFalse
            }
            finally
            {
                $reader.Dispose()
            }
        }
        finally
        {
            [Microsoft.Data.Sqlite.SqliteConnection]::ClearPool($connection)
            $connection.Dispose()
        }
    }
}
