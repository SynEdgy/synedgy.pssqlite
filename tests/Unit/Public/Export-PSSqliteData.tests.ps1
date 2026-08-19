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
    function New-ExportTestConfig
    {
        $databasePath = Join-Path -Path $TestDrive -ChildPath 'db'
        $configPath = Join-Path -Path $TestDrive -ChildPath 'Export.PSSqliteConfig.yml'
        $null = New-Item -Path $databasePath -ItemType Directory -Force

        @"
DatabasePath: '$databasePath'
DatabaseFile: 'export.sqlite'
Version: '1.0.0'
Schema:
  Tables:
    Files:
      Columns:
        Id:
          Type: INTEGER
          PrimaryKey: true
          AllowNull: false
        Name:
          Type: TEXT
        Content:
          Type: BLOB
        Notes:
          Type: TEXT
"@ | Set-Content -Path $configPath

        Get-PSSqliteDBConfig -Path $configPath
    }
}

Describe 'Export-PSSqliteData' {
    It 'Should export configured tables and encode blob values' {
        $config = New-ExportTestConfig
        Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop
        $connection = New-PSSqliteConnection -ConnectionString $config.ConnectionString

        try
        {
            $connection.Open()
            $command = $connection.CreateCommand()
            $command.CommandText = 'INSERT INTO Files (Name, Content, Notes) VALUES (@name, @content, NULL);'
            $null = $command.Parameters.AddWithValue('@name', 'readme')
            $null = $command.Parameters.AddWithValue('@content', [byte[]](1, 2, 3, 255))
            $null = $command.ExecuteNonQuery()
        }
        finally
        {
            [Microsoft.Data.Sqlite.SqliteConnection]::ClearPool($connection)
            $connection.Dispose()
        }

        $dumpPath = Join-Path -Path $TestDrive -ChildPath 'dump'
        $result = Export-PSSqliteData -SqliteDBConfig $config -Path $dumpPath -ErrorAction Stop

        $result.TableCount | Should -Be 1
        $result.RowCount | Should -Be 1
        Test-Path -Path $result.ManifestPath | Should -BeTrue

        $manifest = Get-Content -Path $result.ManifestPath -Raw | ConvertFrom-Json
        $manifest.Tables[0].File | Should -Match '^0001-Files_\d{4}-\d{2}-\d{2}_\d{2}\.\d{2}\.\d{2}\.json$'
        $tableDump = Get-Content -Path (Join-Path -Path $dumpPath -ChildPath $manifest.Tables[0].File) -Raw | ConvertFrom-Json
        $tableDump.Rows[0].Content.PSSqliteType | Should -Be 'Blob'
        $tableDump.Rows[0].Content.Value | Should -Be 'AQID/w=='
        $tableDump.Rows[0].Notes | Should -BeNullOrEmpty
    }

    It 'Should require Force before overwriting an existing dump' {
        $config = New-ExportTestConfig
        Initialize-PSSqliteDatabase -DatabaseConfig $config -ErrorAction Stop
        $dumpPath = Join-Path -Path $TestDrive -ChildPath 'existing-dump'

        $null = Export-PSSqliteData -SqliteDBConfig $config -Path $dumpPath -ErrorAction Stop

        { Export-PSSqliteData -SqliteDBConfig $config -Path $dumpPath -ErrorAction Stop } |
            Should -Throw '*Use Force to overwrite*'
    }
}
