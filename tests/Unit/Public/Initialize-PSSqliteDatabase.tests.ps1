BeforeDiscovery {
    $projectPath = "$($PSScriptRoot)\..\.." | Convert-Path

    if (-not $ProjectName)
    {
        $ProjectName = Get-SamplerProjectName -BuildRoot $projectPath
    }

    $script:moduleName = $ProjectName

    Remove-Module -Name $script:moduleName -Force -ErrorAction SilentlyContinue

    $null = Get-Module -Name $script:moduleName -ListAvailable |
        Select-Object -First 1 |
        Import-Module -Force -ErrorAction Stop -PassThru |
        Where-Object -FilterScript { $_.Guid -ne [guid]::Empty }
}

BeforeAll {
    function New-TestSqliteDbConfig
    {
        param
        (
            [string]
            $Version = '1.0.0',

            [switch]
            $IncludeModel
        )

        $testRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $databasePath = Join-Path -Path $testRoot -ChildPath 'db'
        $configPath = Join-Path -Path $testRoot -ChildPath 'Pester.PSSqliteConfig.yml'

        $null = New-Item -Path $databasePath -ItemType Directory -Force

        if ($IncludeModel)
        {
            $modelColumn = @"
        Model:
          Type: INTEGER
          DefaultValue: 0
"@
        }

        @"
DatabasePath: '$databasePath'
DatabaseFile: 'Pester.sqlite'
Version: '$Version'
Schema:
  Tables:
    Cars:
      Columns:
        Id:
          Type: INTEGER
          PrimaryKey: true
          AllowNull: false
        Make:
          Type: TEXT
        Colour:
          Type: TEXT
        Year:
          Type: INTEGER
$modelColumn
"@ | Set-Content -Path $configPath -NoNewline

        Get-PSSqliteDBConfig -Path $configPath
    }

    function New-TestSqliteViewDbConfig
    {
        $testRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $databasePath = Join-Path -Path $testRoot -ChildPath 'db'
        $configPath = Join-Path -Path $testRoot -ChildPath 'Pester.PSSqliteConfig.yml'

        $null = New-Item -Path $databasePath -ItemType Directory -Force

        @"
DatabasePath: '$databasePath'
DatabaseFile: 'Pester.sqlite'
Version: '1.3.0'
Schema:
  Tables:
    Makes:
      Columns:
        Id:
          Type: INTEGER
          PrimaryKey: true
          AllowNull: false
        Name:
          Type: TEXT
    Cars:
      Columns:
        Id:
          Type: INTEGER
          PrimaryKey: true
          AllowNull: false
        MakeId:
          Type: INTEGER
        Model:
          Type: TEXT
  Views:
    CarSummary:
      Columns:
        CarId:
          Source:
            Table: c
            Column: Id
        MakeName:
          Source:
            Table: m
            Column: Name
        Model:
          Source:
            Table: c
            Column: Model
      From:
        Table: Cars
        Alias: c
      Joins:
        - Type: Inner
          Table: Makes
          Alias: m
          On:
            All:
              - Left:
                  Table: c
                  Column: MakeId
                Operator: '='
                Right:
                  Table: m
                  Column: Id
"@ | Set-Content -Path $configPath -NoNewline

        Get-PSSqliteDBConfig -Path $configPath
    }
}

Describe 'Initialize-PSSqliteDatabase' {
    It 'Should initialize a database from YAML config and track the deployed schema version' {
        $config = New-TestSqliteDbConfig -Version '1.2.3'

        Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop

        Test-Path -Path (Join-Path -Path $config.DatabasePath -ChildPath $config.DatabaseFile) | Should -BeTrue

        $compareResult = Compare-PSSqliteDBVersion -DatabaseConfig $config -ExpectedVersion '1.2.3'
        $compareResult.IsDeployed | Should -BeTrue
        $compareResult.CurrentVersion | Should -Be '1.2.3'
        $compareResult.ExpectedVersion | Should -Be '1.2.3'
        $compareResult.direction | Should -Be '=='

        $connection = New-PSSqliteConnection -ConnectionString $config.ConnectionString

        try
        {
            $metadata = Get-PSSqliteDBMetadata -SqliteConnection $connection -MetadataKey 'version'
            $metadata['version'] | Should -Be '1.2.3'
        }
        finally
        {
            $connection.Dispose()
        }
    }

    It 'Should create structured views defined in the YAML schema' {
        $config = New-TestSqliteViewDbConfig

        Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop

        $connection = New-PSSqliteConnection -ConnectionString $config.ConnectionString

        try
        {
            $viewDefinition = @(Invoke-PSSqliteQuery -SqliteConnection $connection -CommandText @'
SELECT name, sql
FROM sqlite_master
WHERE type = 'view'
  AND name = 'CarSummary';
'@ -As 'PSCustomObject' -ErrorAction Stop)

            $viewDefinition.Count | Should -Be 1
            $viewDefinition[0].name | Should -Be 'CarSummary'
            $viewDefinition[0].sql | Should -Match 'CREATE VIEW'
        }
        finally
        {
            $connection.Dispose()
        }
    }

    It 'Should preserve compatible data during an overwrite migration' {
        $config = New-TestSqliteDbConfig -Version '1.0.0'
        Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop
        $null = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -RowData ([ordered]@{
            Make = 'Toyota'
            Colour = 'Yellow'
            Year = 2024
        }) -ErrorAction Stop

        $newConfig = New-TestSqliteDbConfig -Version '2.0.0' -IncludeModel
        $newConfig.DatabasePath = $config.DatabasePath
        $newConfig.DatabaseFile = $config.DatabaseFile
        $newConfig.ConnectionString = $config.ConnectionString
        $backupPath = Join-Path -Path $TestDrive -ChildPath 'migration-backup'

        Initialize-PSSqliteDatabase -DatabaseConfig $newConfig -MigrationMode OVERWRITE -DataBackupPath $backupPath -ErrorAction Stop

        Test-Path -Path (Join-Path -Path $backupPath -ChildPath '_manifest.json') | Should -BeTrue
        @(Get-ChildItem -Path $backupPath -Filter 'Pester_????-??-??_??.??.??.bak.db').Count | Should -Be 1
        $rows = @(Get-PSSqliteRow -SqliteDBConfig $newConfig -TableName 'Cars' -ErrorAction Stop)
        $rows.Count | Should -Be 1
        $rows[0].Make | Should -Be 'Toyota'
        $rows[0].Model | Should -Be 0
    }

    It 'Should remove existing data when NoPreserveData is specified' {
        $config = New-TestSqliteDbConfig -Version '1.0.0'
        Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop
        $null = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -RowData ([ordered]@{
            Make = 'Toyota'
            Colour = 'Yellow'
            Year = 2024
        }) -ErrorAction Stop

        $newConfig = New-TestSqliteDbConfig -Version '2.0.0' -IncludeModel
        $newConfig.DatabasePath = $config.DatabasePath
        $newConfig.DatabaseFile = $config.DatabaseFile
        $newConfig.ConnectionString = $config.ConnectionString

        Initialize-PSSqliteDatabase -DatabaseConfig $newConfig -MigrationMode OVERWRITE -NoPreserveData -ErrorAction Stop

        @(Get-PSSqliteRow -SqliteDBConfig $newConfig -TableName 'Cars' -ErrorAction Stop).Count | Should -Be 0
    }
}
