BeforeDiscovery {
    $supportsJsonSchema = [bool](Get-Command Test-Json -ErrorAction SilentlyContinue)
}

Describe 'Publishable PSSqlite configuration schema' -Skip:(-not $supportsJsonSchema) {
    BeforeAll {
        $module = Import-Module synedgy.PSSqlite -Force -ErrorAction Stop -PassThru |
            Where-Object { $_.Guid -ne [guid]::Empty } |
            Select-Object -First 1
        $schemaPath = Join-Path (Join-Path $module.ModuleBase 'schemas') 'pssqlite-config.schema.json'
        $projectPath = Join-Path $PSScriptRoot '..\..'
    }

    It 'Should validate the existing YAML example and configuration examples in the README' {
        $yaml = Get-Content -LiteralPath (Join-Path $projectPath 'tests\Unit\Public\Database.yml') -Raw
        $definition = ConvertFrom-Yaml -Yaml $yaml
        Test-PSSqliteConfiguration -Definition $definition -ErrorAction Stop | Should -BeTrue
        $json = $definition | ConvertTo-Json -Depth 100
        Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction Stop | Should -BeTrue
        $readme = Get-Content -LiteralPath (Join-Path $projectPath 'README.md') -Raw
        $examples = @([regex]::Matches($readme, '(?ms)^\$yaml = @''\r?\n(.*?)^''@'))
        $examples += @([regex]::Matches($readme, '(?ms)^```yaml\r?\n(.*?)^```'))
        $examples.Count | Should -BeGreaterThan 0
        foreach ($example in $examples)
        {
            $definition = ConvertFrom-Yaml -Yaml $example.Groups[1].Value
            if (-not $definition -or -not $definition.Schema) { continue }

            $json = $definition | ConvertTo-Json -Depth 100
            Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction Stop | Should -BeTrue
            Test-PSSqliteConfiguration -Definition $definition -ErrorAction Stop | Should -BeTrue
        }
    }

    It 'Should accept case-insensitive keys and integer schema versions' {
        $json = @{
            connectionstring = 'Data Source=:memory:;'
            version = 1
            sChEmA = @{
                tAbLeS = @{
                    example = @{
                        cOlUmNs = @{
                            id = @{ tYpE = 'TEXT'; pRiMaRyKeY = $true }
                        }
                    }
                }
            }
        } | ConvertTo-Json -Depth 100
        Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction Stop | Should -BeTrue
    }

    It 'Should accept setup-only configuration and raw views with declared output columns' {
        $definition = @{
            ConnectionString = 'Data Source=:memory:;'
            Schema = @{ SetupSql = @(@{ Name = 'fts'; Sql = 'CREATE VIRTUAL TABLE search USING fts5(body);' }) }
        }
        Test-Json -Json ($definition | ConvertTo-Json -Depth 100) -SchemaFile $schemaPath -ErrorAction Stop | Should -BeTrue
        $definition.Schema = @{
            Views = @{
                example = @{ Columns = @{ value = @{} }; Sql = 'SELECT 1 AS value' }
            }
        }
        Test-Json -Json ($definition | ConvertTo-Json -Depth 100) -SchemaFile $schemaPath -ErrorAction Stop | Should -BeTrue
    }

    It 'Should accept structured views with explicit column sources and expressions' {
        $definition = @{
            ConnectionString = 'Data Source=:memory:;'
            Schema = @{
                Views = @{
                    example = @{
                        From = 'items'
                        Columns = @{
                            id = @{ Column = 'id' }

                            label = @{ sOuRcE = @{ cOlUmN = 'label'; Table = 'items' } }

                            total = @{ Expression = 'COUNT(*)' }
                        }
                    }
                }
            }
        }
        Test-Json -Json ($definition | ConvertTo-Json -Depth 100) -SchemaFile $schemaPath -ErrorAction Stop | Should -BeTrue
    }

    It 'Should reject invalid configuration structure' -ForEach @(
        @{ Definition = @{ ConnectionString = 'Data Source=:memory:'; Schema = @{ SetpuSql = @() } } }
        @{ Definition = @{ ConnectionString = 'Data Source=:memory:'; Schema = @{ Tables = @{ example = @{ Columns = @{ id = @{ PrimaryKey = $true } } } } } } }
        @{ Definition = @{ DatabaseFile = 'test.db'; Schema = @{ SetupSql = @(@{ Name = 'example'; Sql = 'SELECT 1' }) } } }
        @{ Definition = @{ ConnectionString = 'Data Source=:memory:'; Schema = @{ SetupSql = @(@{ Name = 'empty'; Sql = '' }) } } }
        @{ Definition = @{ ConnectionString = 'Data Source=:memory:'; Schema = @{ SetupSql = @(@{ Name = 'unsupported'; Path = 'setup.sql' }) } } }
        @{ Definition = @{ ConnectionString = 'Data Source=:memory:'; Schema = @{ Tables = @{ example = @{ Columns = @{ id = @{ Type = 'VARCHAR' } } } } } } }
        @{ Definition = @{ ConnectionString = 'Data Source=:memory:'; Schema = @{ Views = @{ example = @{ Columns = @{ id = @{} }; Sql = 'SELECT 1'; From = 'other' } } } } }
        @{ Definition = @{ ConnectionString = 'Data Source=:memory:'; Schema = @{ Views = @{ example = @{ Columns = @{ id = @{} }; Sql = 'SELECT 1'; Where = 'id = 1' } } } } }
        @{ Definition = @{ ConnectionString = 'Data Source=:memory:'; Schema = @{ Views = @{ example = @{ Columns = @{ id = @{} }; From = 'other' } } } } }
        @{ Definition = @{ ConnectionString = 'Data Source=:memory:'; Schema = @{ Views = @{ example = @{ Columns = @{ id = @{ Source = @{ Name = 'id' } } }; From = 'other' } } } } }
        @{ Definition = @{ ConnectionString = 'Data Source=:memory:'; Schema = @{ Tables = @{ example = @{ Columns = @{ id = @{ Type = 'TEXT' } }; Constraints = @(@{ Type = 'ForeignKey'; Name = 'fk'; Columns = @('id'); ForeignTable = 'other' }) } } } } }
    ) {
        $json = $Definition | ConvertTo-Json -Depth 100
        Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction SilentlyContinue | Should -BeFalse
        @(Test-PSSqliteConfiguration -Definition $Definition -Detailed).Count | Should -BeGreaterThan 0
    }
}
