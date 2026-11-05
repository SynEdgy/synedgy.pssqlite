function Get-PSSqliteDefinitionIssue
{
    <#
    .SYNOPSIS
    Checks the structure of an unexpanded PSSqlite definition.
    .DESCRIPTION
    Validates recognised keys and value types before class constructors can
    coerce them. This is a PSSqlite contract checker, not a JSON Schema engine.
    .PARAMETER Value
    The value being checked.
    .PARAMETER Kind
    The PSSqlite configuration node or scalar type.
    .PARAMETER Path
    The diagnostic path of the value.
    .PARAMETER CleanValue
    Receives a copy containing only recognised configuration properties.
    .EXAMPLE
    Get-PSSqliteDefinitionIssue -Value $definition -Kind configuration
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()][object] $Value,
        [string] $Kind = 'configuration',
        [string] $Path = '$',
        [ref] $CleanValue
    )

    if (-not $CleanValue) { $CleanValue = [ref]$null }

    $CleanValue.Value = $Value
    $message = $null
    $fields = $null
    $required = @()
    if ($Kind -like 'map:*')
    {
        if ($Value -isnot [System.Collections.IDictionary] -or $Value.Count -eq 0)
        {
            $message = 'Expected a non-empty mapping.'
        }
        else
        {
            $clean = [ordered]@{}

            $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($key in $Value.Keys)
            {
                if ($key -isnot [string] -or [string]::IsNullOrWhiteSpace($key) -or -not $names.Add($key))
                {
                    [pscustomobject]@{ Path = "$Path.$key"; Code = 'InvalidName'; Message = 'Names must be non-empty strings and unique ignoring case.' }
                }

                $child = $null
                Get-PSSqliteDefinitionIssue -Value $Value[$key] -Kind $Kind.Substring(4) -Path "$Path.$key" -CleanValue ([ref]$child)
                $clean[$key] = $child
            }

            $CleanValue.Value = $clean
        }
    }
    elseif ($Kind -like 'list:*')
    {
        if ($Value -isnot [System.Collections.IList])
        {
            $message = 'Expected a list.'
        }
        else
        {
            $clean = [System.Collections.Generic.List[object]]::new()
            for ($index = 0; $index -lt $Value.Count; $index++)
            {
                $child = $null
                Get-PSSqliteDefinitionIssue -Value $Value[$index] -Kind $Kind.Substring(5) -Path "$Path[$index]" -CleanValue ([ref]$child)
                $clean.Add($child)
            }

            $CleanValue.Value = $clean.ToArray()
        }
    }
    elseif ($Kind -like 'enum:*')
    {
        $allowed = $Kind.Substring(5).Split('|')
        if ($Value -isnot [string] -or $Value -notin $allowed)
        {
            $message = 'Expected one of: {0}.' -f ($allowed -join ', ')
        }
    }
    else
    {
        $isNumber = $Value -is [byte] -or $Value -is [sbyte] -or
            $Value -is [int16] -or $Value -is [uint16] -or
            $Value -is [int32] -or $Value -is [uint32] -or
            $Value -is [int64] -or $Value -is [uint64] -or
            $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]
        switch ($Kind)
        {
            'text'
            {
                if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) { $message = 'Expected a non-empty string.' }
            }

            'boolean'
            {
                if ($Value -isnot [bool]) { $message = 'Expected a Boolean, not a string or number.' }
            }

            'default'
            {
                if ($null -ne $Value -and $Value -isnot [string] -and -not $isNumber) { $message = 'Expected a SQL expression string, number or null.' }
            }

            'version'
            {
                if (($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) -and
                    (-not $isNumber -or $Value -lt 0 -or $Value % 1 -ne 0))
                {
                    $message = 'Expected a non-empty version string or non-negative integer.'
                }
            }

            'configuration'
            {
                $fields = @{ '$schema' = 'text'; DatabasePath = 'text'; DatabaseFile = 'text'; ConnectionString = 'text'; Version = 'version'; Schema = 'schema' }

                $required = @('Schema')
            }

            'schema'
            {
                $fields = @{ Tables = 'map:table'; Views = 'map:view'; Indexes = 'map:index'; SetupSql = 'list:setup' }
            }

            'table'
            {
                $fields = @{ Columns = 'map:column'; Constraints = 'list:constraint'; Options = 'list:enum:Strict|WithoutRowId'; Schema = 'text'; IfNotExists = 'boolean' }

                $required = @('Columns')
            }

            'column'
            {
                $fields = @{
                    Type = 'enum:INTEGER|TEXT|REAL|BLOB'; PrimaryKey = 'boolean'; PrimaryKeyOrder = 'enum:ASC|DESC|NONE'
                    AutoIncrement = 'boolean'; AllowNull = 'boolean'; Unique = 'boolean'; Indexed = 'boolean'
                    UniqueConflictClause = 'enum:NONE|ROLLBACK|ABORT|FAIL|IGNORE|REPLACE'
                    CheckExpression = 'text'; DefaultValue = 'default'; Collation = 'text'; References = 'text'
                }

                $required = @('Type')
            }

            'constraint'
            {
                $fields = @{
                    Type = 'enum:PrimaryKey|ForeignKey|Check|Index'; Name = 'text'; Columns = 'list:text'
                    ForeignTable = 'text'; ForeignColumns = 'list:text'; OnUpdate = 'enum:NO ACTION|RESTRICT|SET NULL|SET DEFAULT|CASCADE'
                    OnDelete = 'enum:NO ACTION|RESTRICT|SET NULL|SET DEFAULT|CASCADE'; Match = 'text'; CheckExpression = 'text'
                    ConflictClause = 'enum:NONE|ROLLBACK|ABORT|FAIL|IGNORE|REPLACE'; Unique = 'boolean'
                    IfNotExists = 'boolean'; SchemaName = 'text'; Where = 'text'; TableName = 'text'; ColumnName = 'text'
                }

                $required = @('Type')
            }

            'index'
            {
                $fields = @{ Name = 'text'; Table = 'text'; Columns = 'list:text'; Unique = 'boolean'; IfNotExists = 'boolean'; SchemaName = 'text'; Where = 'text' }

                $required = @('Table', 'Columns')
            }

            'setup'
            {
                $fields = @{ Name = 'text'; Sql = 'text' }

                $required = @('Name', 'Sql')
            }

            'view'
            {
                $fields = @{
                    Schema = 'text'; IfNotExists = 'boolean'; Columns = 'map:viewColumn'; Select = 'select'
                    Distinct = 'boolean'; Sql = 'text'; From = 'source'; Joins = 'list:join'
                    Where = 'condition'; Having = 'condition'; GroupBy = 'groupBy'; OrderBy = 'list:orderItem'
                }
            }

            'select'
            {
                $fields = @{ Columns = 'map:viewColumn'; Distinct = 'boolean' }
            }

            'viewColumn'
            {
                if ($null -eq $Value) { return }

                $fields = @{ Table = 'text'; Column = 'text'; Expression = 'text'; Source = 'reference' }
            }

            'source'
            {
                if ($Value -is [string])
                {
                    Get-PSSqliteDefinitionIssue -Value $Value -Kind text -Path $Path
                    return
                }

                $fields = @{ Table = 'text'; Name = 'text'; Alias = 'text' }
            }

            'reference'
            {
                if ($Value -is [string])
                {
                    Get-PSSqliteDefinitionIssue -Value $Value -Kind text -Path $Path
                    return
                }

                $fields = @{ Table = 'text'; Alias = 'text'; Column = 'text'; Name = 'text'; Expression = 'text' }
            }

            'operand'
            {
                if ($null -eq $Value -or $Value -is [string] -or $Value -is [bool] -or $isNumber) { return }

                if ($Value -is [System.Collections.IList])
                {
                    Get-PSSqliteDefinitionIssue -Value $Value -Kind 'list:operand' -Path $Path -CleanValue $CleanValue
                    return
                }

                $fields = @{ Table = 'text'; Alias = 'text'; Column = 'text'; Name = 'text'; Expression = 'text'; Value = 'literal' }
            }

            'literal'
            {
                if ($null -ne $Value -and $Value -isnot [string] -and $Value -isnot [bool] -and -not $isNumber) { $message = 'Expected a scalar literal or null.' }
            }

            'condition'
            {
                if ($Value -is [string])
                {
                    Get-PSSqliteDefinitionIssue -Value $Value -Kind text -Path $Path
                    return
                }

                $fields = @{ All = 'list:condition'; Any = 'list:condition'; Left = 'reference'; Operator = 'text'; Right = 'operand' }
            }

            'join'
            {
                $fields = @{ Type = 'text'; Table = 'text'; Name = 'text'; Alias = 'text'; On = 'condition' }

                $required = @('On')
            }

            'groupBy'
            {
                if ($Value -is [System.Collections.IList])
                {
                    Get-PSSqliteDefinitionIssue -Value $Value -Kind 'list:reference' -Path $Path -CleanValue $CleanValue
                    return
                }

                $fields = @{ Columns = 'list:reference' }

                $required = @('Columns')
            }

            'orderItem'
            {
                if ($Value -is [string])
                {
                    Get-PSSqliteDefinitionIssue -Value $Value -Kind text -Path $Path
                    return
                }

                $fields = @{ Table = 'text'; Alias = 'text'; Column = 'text'; Name = 'text'; Expression = 'text'; Direction = 'enum:ASC|DESC' }
            }

            default { throw [ArgumentException]::new("Unknown validation kind '$Kind'.") }
        }
    }

    if ($null -ne $fields)
    {
        if ($Value -isnot [System.Collections.IDictionary])
        {
            $message = 'Expected a mapping.'
        }
        else
        {
            $clean = [ordered]@{}

            $keys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($key in $Value.Keys)
            {
                if ($key -is [string] -and -not $fields.ContainsKey($key)) { continue }

                if ($key -isnot [string] -or -not $keys.Add($key))
                {
                    [pscustomobject]@{ Path = "$Path.$key"; Code = 'InvalidKey'; Message = 'Property names must be strings and unique ignoring case.' }
                }
                else
                {
                    $child = $null
                    Get-PSSqliteDefinitionIssue -Value $Value[$key] -Kind $fields[$key] -Path "$Path.$key" -CleanValue ([ref]$child)
                    $clean[$key] = $child
                }
            }

            $CleanValue.Value = $clean

            foreach ($key in $required)
            {
                if (-not $keys.Contains($key))
                {
                    [pscustomobject]@{ Path = "$Path.$key"; Code = 'MissingProperty'; Message = "Required property '$key' is missing." }
                }
            }

            if ($Kind -eq 'configuration')
            {
                if (-not $keys.Contains('ConnectionString') -and
                    (-not $keys.Contains('DatabasePath') -or -not $keys.Contains('DatabaseFile')))
                {
                    [pscustomobject]@{ Path = $Path; Code = 'MissingConnection'; Message = 'Provide ConnectionString or both DatabasePath and DatabaseFile.' }
                }
            }

            if ($Kind -eq 'schema' -and -not ($keys.Contains('Tables') -or $keys.Contains('Views') -or $keys.Contains('SetupSql')))
            {
                [pscustomobject]@{ Path = $Path; Code = 'MissingSchema'; Message = 'Provide Tables, Views or SetupSql.' }
            }
        }
    }

    if ($message)
    {
        [pscustomobject]@{ Path = $Path; Code = 'InvalidType'; Message = $message }
    }
}
