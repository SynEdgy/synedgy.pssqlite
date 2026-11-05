BeforeAll {
    Import-Module synedgy.PSSqlite -Force -ErrorAction Stop

    function New-ValidationDefinition
    {
        @{
            DatabasePath = '$Env:PSSqliteValidationMissing\state'
            DatabaseFile = 'validation.db'
            Schema = @{
                Tables = @{
                    users = @{
                        Columns = @{
                            id = @{ Type = 'TEXT'; AllowNull = $false }
                        }
                    }
                }
            }
        }
    }
}

Describe 'Shared PSSqlite configuration validation' {
    It 'Should validate unexpanded paths without executing setup SQL or changing the definition' {
        $definition = New-ValidationDefinition
        $definition.Schema.SetupSql = @(@{ Name = 'trusted'; Sql = 'INVALID SQL;' })
        $before = $definition | ConvertTo-Json -Depth 100
        Test-PSSqliteConfiguration -Definition $definition -ErrorAction Stop | Should -BeTrue
        @(Test-PSSqliteConfiguration -Definition $definition -Detailed).Count | Should -Be 0
        ($definition | ConvertTo-Json -Depth 100) | Should -Be $before
        Test-Path -LiteralPath (Join-Path $TestDrive 'validation.db') | Should -BeFalse
    }

    It 'Should return all structural diagnostics before coercing values' {
        $definition = New-ValidationDefinition
        $definition.Schema.Tables.users.Columns.id.AllowNull = 'false'
        $definition.Schema.Tables.users.Columns.id.Tpye = 'TEXT'
        $issues = @(Test-PSSqliteConfiguration -Definition $definition -Detailed)
        $issues.Count | Should -Be 1
        $issues.Path | Should -Contain '$.Schema.Tables.users.Columns.id.AllowNull'
        $issues.Code | Should -Contain 'InvalidType'
        $errors = @()
        Test-PSSqliteConfiguration -Definition $definition -ErrorAction SilentlyContinue -ErrorVariable errors | Should -BeFalse
        $errors.Count | Should -Be 1
        { Test-PSSqliteConfiguration -Definition $definition -ErrorAction Stop } | Should -Throw '*users.Columns.id*'
        { [synedgy.PSSqlite.SQLiteDBConfig]::new($definition) } | Should -Throw '*Invalid PSSqlite configuration*'
    }

    It 'Should reuse semantic checks for duplicate setup names and constraint columns' {
        $definition = New-ValidationDefinition
        $definition.Schema.SetupSql = @(
            @{ Name = 'same'; Sql = 'SELECT 1' }

            @{ Name = 'SAME'; Sql = 'SELECT 2' }
        )
        (Test-PSSqliteConfiguration -Definition $definition -Detailed).Message | Should -BeLike '*unique*'
        $definition.Schema.Remove('SetupSql')
        $definition.Schema.Tables.users.Constraints = @(@{ Type = 'PrimaryKey'; Columns = @('missing') })
        (Test-PSSqliteConfiguration -Definition $definition -Detailed).Message | Should -BeLike '*unknown column*'
    }

    It 'Should ignore custom metadata at every configuration level without modifying it' {
        $definition = New-ValidationDefinition
        $definition.DatabasePath = $TestDrive
        $definition.Documentation = @{ Link = 'custom'; Content = @('notes') }

        $definition.Schema.Notes = 'custom schema information'
        $definition.Schema.Tables.users.Owner = 'custom owner'
        $definition.Schema.Tables.users.Columns.id.Help = @{ Example = 1 }

        $definition.Schema.SetupSql = @(@{ Name = 'example'; Sql = 'SELECT 1'; Notes = 'custom SQL documentation' })
        $before = $definition | ConvertTo-Json -Depth 100
        Test-PSSqliteConfiguration -Definition $definition -ErrorAction Stop | Should -BeTrue
        $null = [synedgy.PSSqlite.SQLiteDBConfig]::new($definition)
        ($definition | ConvertTo-Json -Depth 100) | Should -Be $before
    }

    It 'Should share file validation with the loader and preserve caller dictionaries' {
        $definition = New-ValidationDefinition
        $definition.DatabasePath = $TestDrive
        $path = Join-Path $TestDrive 'Example.PSSqliteConfig.yml'
        ConvertTo-Yaml -Data $definition | Set-Content -LiteralPath $path
        Test-PSSqliteConfiguration -Path $path -ErrorAction Stop | Should -BeTrue
        (Get-PSSqliteDBConfig -Path $path).Schema.Tables[0].Columns[0].Name | Should -Be 'id'
        $before = $definition | ConvertTo-Json -Depth 100
        $null = [synedgy.PSSqlite.SQLiteDBConfig]::new($definition)
        ($definition | ConvertTo-Json -Depth 100) | Should -Be $before
        Test-Path -LiteralPath (Join-Path $TestDrive 'validation.db') | Should -BeFalse
        $definition.Schema.Tables.users.Columns.id.AllowNull = 'false'
        ConvertTo-Yaml -Data $definition | Set-Content -LiteralPath $path
        { Get-PSSqliteDBConfig -Path $path } | Should -Throw '*Expected a Boolean*'
    }

    It 'Should reject invalid roots and report file or YAML failures explicitly' {
        @(Test-PSSqliteConfiguration -Definition @() -Detailed)[0].Code | Should -Be 'InvalidType'
        @(Test-PSSqliteConfiguration -Definition $null -Detailed)[0].Code | Should -Be 'InvalidType'
        { Test-PSSqliteConfiguration -Path (Join-Path $TestDrive 'missing.yml') -Detailed } | Should -Throw
        $path = Join-Path $TestDrive 'malformed.yml'
        'Schema: [invalid' | Set-Content -LiteralPath $path
        { Test-PSSqliteConfiguration -Path $path -Detailed } | Should -Throw
    }

    It 'Should preserve connection-only and parameterless construction' {
        ([synedgy.PSSqlite.SQLiteDBConfig]::new('Data Source=:memory:;')).ConnectionString | Should -Be 'Data Source=:memory:;'
        { [synedgy.PSSqlite.SQLiteDBConfig]::new() } | Should -Not -Throw
    }
}
