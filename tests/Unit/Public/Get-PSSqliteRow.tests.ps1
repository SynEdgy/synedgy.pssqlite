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
}
