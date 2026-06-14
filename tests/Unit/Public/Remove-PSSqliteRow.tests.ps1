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

Describe 'Remove-PSSqliteRow' {
    It 'Should delete rows selected by clause data' {
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

        $null = Remove-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -ClauseData @{ Make = 'Toy*' } -ErrorAction Stop

        $remainingRows = @(Get-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -ErrorAction Stop)
        $remainingRows.Count | Should -Be 1
        $remainingRows[0].Make | Should -Be 'Ford'
    }
}
