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
        Where-Object -FilterScript { $_.Guid -ne (New-Guid -InputObject '00000000-0000-0000-0000-000000000000') }
}

BeforeAll {
    function New-TestSqliteDbConfig
    {
        $testRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().Guid)
        $databasePath = Join-Path -Path $testRoot -ChildPath 'db'
        $configPath = Join-Path -Path $testRoot -ChildPath 'Pester.PSSqliteConfig.yml'

        $null = New-Item -Path $databasePath -ItemType Directory -Force

        @"
DatabasePath: '$databasePath'
DatabaseFile: 'Pester.sqlite'
Version: '1.0.0'
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
Version: '2.0.0'
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
        Colour:
          Type: TEXT
        Year:
          Type: INTEGER
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
        Colour:
          Source:
            Table: c
            Column: Colour
        Year:
          Source:
            Table: c
            Column: Year
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
      OrderBy:
        - Column: CarId
          Direction: Asc
    YellowCars:
      Columns:
        CarId: {}
        Model: {}
        Colour: {}
      Sql: |
        SELECT Id AS CarId, Model, Colour
        FROM Cars
        WHERE Colour = 'Yellow'
    CarSummaryByTableName:
      Columns:
        CarId:
          Source:
            Table: Cars
            Column: Id
        MakeName:
          Source:
            Table: Makes
            Column: Name
        Model:
          Source:
            Table: Cars
            Column: Model
        Colour:
          Source:
            Table: Cars
            Column: Colour
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

Describe 'Get-PSSqliteRow' {
    It 'Should return all rows and support case-insensitive wildcard filtering' {
        $config = New-TestSqliteDbConfig

        Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop
        $null = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -RowData ([ordered]@{
            Make = 'Toyota'
            Colour = 'Yellow'
            Year = 2024
        }) -ErrorAction Stop
        $null = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -RowData ([ordered]@{
            Make = 'Ford'
            Colour = 'Blue'
            Year = 2020
        }) -ErrorAction Stop

        $allRows = @(Get-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -ErrorAction Stop)
        $allRows.Count | Should -Be 2

        $yellowRow = @(Get-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -ClauseData @{ Colour = 'yel*' } -ErrorAction Stop)
        $yellowRow.Count | Should -Be 1
        $yellowRow[0].Make | Should -Be 'Toyota'
        $yellowRow[0].Colour | Should -Be 'Yellow'
    }

    It 'Should support Before and After clause suffixes for numeric values' {
        $config = New-TestSqliteDbConfig

        Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop
        $null = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -RowData ([ordered]@{
            Make = 'Peugeot'
            Colour = 'Green'
            Year = 2018
        }) -ErrorAction Stop
        $null = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -RowData ([ordered]@{
            Make = 'Tesla'
            Colour = 'Red'
            Year = 2024
        }) -ErrorAction Stop

        $beforeRows = @(Get-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -ClauseData @{ YearBefore = 2020 } -ErrorAction Stop)
        $beforeRows.Count | Should -Be 1
        $beforeRows[0].Make | Should -Be 'Peugeot'

        $afterRows = @(Get-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -ClauseData @{ YearAfter = 2020 } -ErrorAction Stop)
        $afterRows.Count | Should -Be 1
        $afterRows[0].Make | Should -Be 'Tesla'
    }

    It 'Should query structured views using declared output columns' {
        $config = New-TestSqliteViewDbConfig

        Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop

        $toyota = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Makes' -RowData ([ordered]@{
            Name = 'Toyota'
        }) -ErrorAction Stop
        $ford = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Makes' -RowData ([ordered]@{
            Name = 'Ford'
        }) -ErrorAction Stop

        $null = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -RowData ([ordered]@{
            MakeId = $toyota.Id
            Model = 'Corolla'
            Colour = 'Yellow'
            Year = 2024
        }) -ErrorAction Stop
        $null = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -RowData ([ordered]@{
            MakeId = $ford.Id
            Model = 'Focus'
            Colour = 'Blue'
            Year = 2019
        }) -ErrorAction Stop

        $viewRows = @(Get-PSSqliteRow -SqliteDBConfig $config -TableName 'CarSummary' -ClauseData @{
            MakeName = 'toy*'
            YearAfter = 2020
        } -ErrorAction Stop)

        $viewRows.Count | Should -Be 1
        $viewRows[0].MakeName | Should -Be 'Toyota'
        $viewRows[0].Model | Should -Be 'Corolla'
        $viewRows[0].Colour | Should -Be 'Yellow'
    }

    It 'Should query raw SQL views using declared output columns for filtering' {
        $config = New-TestSqliteViewDbConfig

        Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop

        $toyota = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Makes' -RowData ([ordered]@{
            Name = 'Toyota'
        }) -ErrorAction Stop

        $null = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -RowData ([ordered]@{
            MakeId = $toyota.Id
            Model = 'Corolla'
            Colour = 'Yellow'
            Year = 2024
        }) -ErrorAction Stop
        $null = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -RowData ([ordered]@{
            MakeId = $toyota.Id
            Model = 'Camry'
            Colour = 'Black'
            Year = 2021
        }) -ErrorAction Stop

        $yellowRows = @(Get-PSSqliteRow -SqliteDBConfig $config -TableName 'YellowCars' -ClauseData @{
            Model = 'Cor*'
        } -ErrorAction Stop)

        $yellowRows.Count | Should -Be 1
        $yellowRows[0].CarId | Should -Not -BeNullOrEmpty
        $yellowRows[0].Model | Should -Be 'Corolla'
        $yellowRows[0].Colour | Should -Be 'Yellow'
    }

    It 'Should allow structured view columns to reference source tables by table name when aliases are defined' {
        $config = New-TestSqliteViewDbConfig

        Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop

        $toyota = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Makes' -RowData ([ordered]@{
            Name = 'Toyota'
        }) -ErrorAction Stop

        $null = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -RowData ([ordered]@{
            MakeId = $toyota.Id
            Model = 'Corolla'
            Colour = 'Yellow'
            Year = 2024
        }) -ErrorAction Stop

        $viewRows = @(Get-PSSqliteRow -SqliteDBConfig $config -TableName 'CarSummaryByTableName' -ClauseData @{
            MakeName = 'Toy*'
        } -ErrorAction Stop)

        $viewRows.Count | Should -Be 1
        $viewRows[0].MakeName | Should -Be 'Toyota'
        $viewRows[0].Model | Should -Be 'Corolla'
        $viewRows[0].Colour | Should -Be 'Yellow'
    }
}
