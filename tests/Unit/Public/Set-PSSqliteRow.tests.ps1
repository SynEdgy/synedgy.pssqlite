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

Describe 'Set-PSSqliteRow' {
    It 'Should update matching rows and close the provided connection when KeepAlive is not used' {
        $config = New-TestSqliteDbConfig

        Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop

        $connection = New-PSSqliteConnection -ConnectionString $config.ConnectionString

        $insertedRow = New-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -RowData ([ordered]@{
            Make = 'Toyota'
            Colour = 'Yellow'
            Year = 2024
        }) -SqliteConnection $connection -KeepAlive -ErrorAction Stop

        $connection.State | Should -Be 'Open'

        Set-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -RowData @{ Colour = 'Blue' } -ClauseData @{ Id = $insertedRow.Id } -SqliteConnection $connection -ErrorAction Stop

        $connection.State | Should -Be 'Closed'

        $updatedRow = Get-PSSqliteRow -SqliteDBConfig $config -TableName 'Cars' -ClauseData @{ Id = $insertedRow.Id } -ErrorAction Stop
        $updatedRow.Colour | Should -Be 'Blue'

        { Remove-Item -Path (Join-Path -Path $config.DatabasePath -ChildPath $config.DatabaseFile) -Force } | Should -Not -Throw
    }
}
