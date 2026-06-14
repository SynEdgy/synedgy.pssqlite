using namespace System.Collections

class SqliteView
{
    [string]$Name
    [string]$Schema
    [bool] $IfNotExists = $true
    [SqliteViewColumn[]]$Columns = @()
    [bool] $Distinct = $false
    [object] $From
    [object[]] $Joins = @()
    [object] $Where
    [object] $Having
    [object[]] $GroupBy = @()
    [object[]] $OrderBy = @()
    [string] $Sql

    SqliteView()
    {
        # Default constructor
    }

    SqliteView([IDictionary] $Definition)
    {
        $this.Name = $Definition['Name']

        if ($Definition.Keys -contains 'Schema')
        {
            $this.Schema = [string] $Definition['Schema']
        }

        if ($Definition.Keys -contains 'IfNotExists' -and -not [string]::IsNullOrWhiteSpace([string] $Definition['IfNotExists']))
        {
            [bool] $refValue = $this.IfNotExists
            $null = [bool]::TryParse([string] $Definition['IfNotExists'], [ref] $refValue)
            $this.IfNotExists = $refValue
        }

        if ($Definition.Keys -contains 'Columns')
        {
            $this.AddColumns($Definition['Columns'])
        }
        elseif (
            $Definition.Keys -contains 'Select' -and
            $Definition['Select'] -is [IDictionary] -and
            $Definition['Select'].Keys -contains 'Columns'
        )
        {
            $this.AddColumns($Definition['Select']['Columns'])
        }

        if ($Definition.Keys -contains 'Distinct' -and -not [string]::IsNullOrWhiteSpace([string] $Definition['Distinct']))
        {
            [bool] $refValue = $this.Distinct
            $null = [bool]::TryParse([string] $Definition['Distinct'], [ref] $refValue)
            $this.Distinct = $refValue
        }
        elseif (
            $Definition.Keys -contains 'Select' -and
            $Definition['Select'] -is [IDictionary] -and
            $Definition['Select'].Keys -contains 'Distinct' -and
            -not [string]::IsNullOrWhiteSpace([string] $Definition['Select']['Distinct'])
        )
        {
            [bool] $refValue = $this.Distinct
            $null = [bool]::TryParse([string] $Definition['Select']['Distinct'], [ref] $refValue)
            $this.Distinct = $refValue
        }

        if ($Definition.Keys -contains 'From')
        {
            $this.From = $Definition['From']
        }

        if ($Definition.Keys -contains 'Joins')
        {
            $this.Joins = @($Definition['Joins'])
        }

        if ($Definition.Keys -contains 'Where')
        {
            $this.Where = $Definition['Where']
        }

        if ($Definition.Keys -contains 'Having')
        {
            $this.Having = $Definition['Having']
        }

        if ($Definition.Keys -contains 'GroupBy')
        {
            if ($Definition['GroupBy'] -is [IDictionary] -and $Definition['GroupBy'].Keys -contains 'Columns')
            {
                $this.GroupBy = @($Definition['GroupBy']['Columns'])
            }
            else
            {
                $this.GroupBy = @($Definition['GroupBy'])
            }
        }

        if ($Definition.Keys -contains 'OrderBy')
        {
            $this.OrderBy = @($Definition['OrderBy'])
        }

        if ($Definition.Keys -contains 'Sql')
        {
            $this.Sql = [string] $Definition['Sql']
        }

        $this.ValidateDefinition()
    }

    hidden [void] AddColumns([object] $ColumnDefinitions)
    {
        if ($ColumnDefinitions -isnot [IDictionary])
        {
            throw [System.ArgumentException]::new(("Columns for view '{0}' must be defined as a mapping." -f $this.Name))
        }

        foreach ($columnName in $ColumnDefinitions.Keys)
        {
            $currentColumn = $ColumnDefinitions[$columnName]
            if ($currentColumn -isnot [IDictionary])
            {
                $currentColumn = [ordered] @{}
            }

            $currentColumn['Name'] = $columnName
            $this.Columns += [SqliteViewColumn]::new($currentColumn)
        }
    }

    [void] ValidateDefinition()
    {
        if (-not $this.Name)
        {
            throw [System.ArgumentException]::new('View Name is required.')
        }

        if (-not $this.Columns -or $this.Columns.Count -eq 0)
        {
            throw [System.ArgumentException]::new(("At least one output column is required for view '{0}'." -f $this.Name))
        }

        foreach ($column in $this.Columns)
        {
            $column.ValidateDefinition()
        }

        if (-not [string]::IsNullOrWhiteSpace($this.Sql))
        {
            if ($this.From -or $this.Joins.Count -gt 0 -or $this.Where -or $this.GroupBy.Count -gt 0 -or $this.Having -or $this.OrderBy.Count -gt 0 -or $this.Distinct)
            {
                throw [System.ArgumentException]::new(("View '{0}' cannot define both Sql and the structured Select/From/Where members." -f $this.Name))
            }

            return
        }

        if (-not $this.From)
        {
            throw [System.ArgumentException]::new(("Structured view '{0}' must define From." -f $this.Name))
        }

        foreach ($column in $this.Columns)
        {
            if (-not $column.HasSelectExpression())
            {
                throw [System.ArgumentException]::new(("Structured view '{0}' column '{1}' must define Expression or Source.Column." -f $this.Name, $column.Name))
            }
        }
    }

    [string] CreateString()
    {
        $this.ValidateDefinition()
        [System.Text.StringBuilder] $sb = [System.Text.StringBuilder]::new()

        $null = $sb.Append('CREATE VIEW ')
        if ($this.IfNotExists)
        {
            $null = $sb.Append('IF NOT EXISTS ')
        }

        if ($this.Schema)
        {
            $null = $sb.Append(('{0}.' -f $this.Schema))
        }

        $null = $sb.Append(('{0} ({1}) AS' -f $this.Name, ($this.Columns.Name -join ', ')))
        $null = $sb.AppendLine()

        if (-not [string]::IsNullOrWhiteSpace($this.Sql))
        {
            $viewSql = $this.Sql.Trim()
            if (-not $viewSql.EndsWith(';'))
            {
                $viewSql = '{0};' -f $viewSql
            }

            $null = $sb.AppendLine($viewSql)
        }
        else
        {
            $null = $sb.AppendLine(('{0};' -f $this.BuildSelectStatement()))
        }

        return $sb.ToString()
    }

    hidden [string] BuildSelectStatement()
    {
        [System.Text.StringBuilder] $sb = [System.Text.StringBuilder]::new()

        $null = $sb.Append('SELECT ')
        if ($this.Distinct)
        {
            $null = $sb.Append('DISTINCT ')
        }

        $null = $sb.AppendLine(($this.Columns.ForEach{ $this.FormatViewColumn($_) } -join ', '))
        $null = $sb.Append(('FROM {0}' -f $this.FormatSource($this.From)))

        foreach ($joinDefinition in $this.Joins)
        {
            $null = $sb.AppendLine()
            $null = $sb.Append($this.FormatJoin($joinDefinition))
        }

        if ($this.Where)
        {
            $null = $sb.AppendLine()
            $null = $sb.Append(('WHERE {0}' -f $this.FormatCondition($this.Where)))
        }

        if ($this.GroupBy.Count -gt 0)
        {
            $null = $sb.AppendLine()
            $null = $sb.Append(('GROUP BY {0}' -f ($this.GroupBy.ForEach{ $this.FormatReference($_) } -join ', ')))
        }

        if ($this.Having)
        {
            $null = $sb.AppendLine()
            $null = $sb.Append(('HAVING {0}' -f $this.FormatCondition($this.Having)))
        }

        if ($this.OrderBy.Count -gt 0)
        {
            $null = $sb.AppendLine()
            $null = $sb.Append(('ORDER BY {0}' -f ($this.OrderBy.ForEach{ $this.FormatOrderBy($_) } -join ', ')))
        }

        return $sb.ToString().TrimEnd()
    }

    hidden [string] FormatViewColumn([SqliteViewColumn] $Column)
    {
        if (-not [string]::IsNullOrWhiteSpace($Column.Expression))
        {
            return '{0} AS {1}' -f $Column.Expression, $Column.Name
        }

        $referenceDefinition = [ordered] @{
            Table  = $Column.Table
            Column = $Column.Column
        }

        return '{0} AS {1}' -f $this.FormatReference($referenceDefinition), $Column.Name
    }

    hidden [string] FormatSource([object] $Definition)
    {
        if ($Definition -is [string])
        {
            return [string] $Definition
        }

        if ($Definition -isnot [IDictionary])
        {
            throw [System.ArgumentException]::new(("Invalid source definition for view '{0}'." -f $this.Name))
        }

        $tableName = $Definition['Table']
        if (-not $tableName)
        {
            $tableName = $Definition['Name']
        }

        if (-not $tableName)
        {
            throw [System.ArgumentException]::new(("View '{0}' source definitions must include Table or Name." -f $this.Name))
        }

        if ($Definition.Keys -contains 'Alias' -and -not [string]::IsNullOrWhiteSpace([string] $Definition['Alias']))
        {
            return '{0} {1}' -f $tableName, $Definition['Alias']
        }

        return [string] $tableName
    }

    hidden [string] FormatReference([object] $Reference)
    {
        if ($Reference -is [string])
        {
            return [string] $Reference
        }

        if ($Reference -isnot [IDictionary])
        {
            throw [System.ArgumentException]::new(("Invalid reference definition for view '{0}'." -f $this.Name))
        }

        if ($Reference.Keys -contains 'Expression' -and -not [string]::IsNullOrWhiteSpace([string] $Reference['Expression']))
        {
            return [string] $Reference['Expression']
        }

        $columnName = $Reference['Column']
        if (-not $columnName)
        {
            $columnName = $Reference['Name']
        }

        if (-not $columnName)
        {
            throw [System.ArgumentException]::new(("View '{0}' references must include Column or Expression." -f $this.Name))
        }

        $tableName = $Reference['Table']
        if (-not $tableName)
        {
            $tableName = $Reference['Alias']
        }

        if ($tableName)
        {
            return '{0}.{1}' -f $this.ResolveReferencedTable([string] $tableName), $columnName
        }

        return [string] $columnName
    }

    hidden [string] ResolveReferencedTable([string] $TableName)
    {
        if ([string]::IsNullOrWhiteSpace($TableName))
        {
            return $TableName
        }

        foreach ($sourceDefinition in @($this.From) + @($this.Joins))
        {
            if ($sourceDefinition -isnot [IDictionary])
            {
                continue
            }

            $sourceName = $sourceDefinition['Table']
            if (-not $sourceName)
            {
                $sourceName = $sourceDefinition['Name']
            }

            $sourceAlias = $sourceDefinition['Alias']
            if (
                $sourceAlias -and
                (
                    [string]::Equals([string] $TableName, [string] $sourceAlias, [System.StringComparison]::OrdinalIgnoreCase) -or
                    [string]::Equals([string] $TableName, [string] $sourceName, [System.StringComparison]::OrdinalIgnoreCase)
                )
            )
            {
                return [string] $sourceAlias
            }

            if ([string]::Equals([string] $TableName, [string] $sourceName, [System.StringComparison]::OrdinalIgnoreCase))
            {
                return [string] $sourceName
            }
        }

        return $TableName
    }

    hidden [string] FormatOperand([object] $Operand)
    {
        if ($Operand -is [IDictionary])
        {
            if ($Operand.Keys -contains 'Value')
            {
                return $this.ConvertSqlLiteral($Operand['Value'])
            }

            return $this.FormatReference($Operand)
        }

        if ($Operand -is [System.Collections.IEnumerable] -and $Operand -isnot [string])
        {
            return '({0})' -f (($Operand | ForEach-Object { $this.ConvertSqlLiteral($_) }) -join ', ')
        }

        return $this.ConvertSqlLiteral($Operand)
    }

    hidden [string] ConvertSqlLiteral([object] $Value)
    {
        if ($null -eq $Value)
        {
            return 'NULL'
        }

        if ($Value -is [bool])
        {
            if ($Value)
            {
                return '1'
            }

            return '0'
        }

        if ($Value -is [datetime])
        {
            return "'{0}'" -f $Value.ToString('o')
        }

        if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [decimal] -or $Value -is [single] -or $Value -is [double])
        {
            return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $Value)
        }

        return "'{0}'" -f ([string] $Value).Replace("'", "''")
    }

    hidden [string] FormatCondition([object] $Condition)
    {
        if ($Condition -is [string])
        {
            return [string] $Condition
        }

        if ($Condition -isnot [IDictionary])
        {
            throw [System.ArgumentException]::new(("Invalid condition definition for view '{0}'." -f $this.Name))
        }

        if ($Condition.Keys -contains 'All')
        {
            $formattedConditions = @($Condition['All']).ForEach{ $this.FormatCondition($_) }
            if ($formattedConditions.Count -eq 0)
            {
                throw [System.ArgumentException]::new(("Condition group 'All' for view '{0}' must contain at least one condition." -f $this.Name))
            }

            return '({0})' -f ($formattedConditions -join ' AND ')
        }

        if ($Condition.Keys -contains 'Any')
        {
            $formattedConditions = @($Condition['Any']).ForEach{ $this.FormatCondition($_) }
            if ($formattedConditions.Count -eq 0)
            {
                throw [System.ArgumentException]::new(("Condition group 'Any' for view '{0}' must contain at least one condition." -f $this.Name))
            }

            return '({0})' -f ($formattedConditions -join ' OR ')
        }

        if (-not ($Condition.Keys -contains 'Left'))
        {
            throw [System.ArgumentException]::new(("View '{0}' conditions must define Left." -f $this.Name))
        }

        if (-not ($Condition.Keys -contains 'Operator'))
        {
            throw [System.ArgumentException]::new(("View '{0}' conditions must define Operator." -f $this.Name))
        }

        $leftValue = $this.FormatReference($Condition['Left'])
        $operator = [string] $Condition['Operator']
        $normalizedOperator = $operator.ToUpperInvariant()

        if ($Condition.Keys -contains 'Right')
        {
            $rightValue = $this.FormatOperand($Condition['Right'])
            return '{0} {1} {2}' -f $leftValue, $normalizedOperator, $rightValue
        }

        if ($normalizedOperator -in @('IS NULL', 'IS NOT NULL'))
        {
            return '{0} {1}' -f $leftValue, $normalizedOperator
        }

        throw [System.ArgumentException]::new(("View '{0}' condition '{1}' requires Right." -f $this.Name, $operator))
    }

    hidden [string] FormatJoin([object] $JoinDefinition)
    {
        if ($JoinDefinition -isnot [IDictionary])
        {
            throw [System.ArgumentException]::new(("Invalid join definition for view '{0}'." -f $this.Name))
        }

        $joinType = [string] $JoinDefinition['Type']
        if (-not $joinType)
        {
            $joinType = 'INNER'
        }

        $joinSource = [ordered] @{}
        if ($JoinDefinition.Keys -contains 'Table')
        {
            $joinSource['Table'] = $JoinDefinition['Table']
        }
        elseif ($JoinDefinition.Keys -contains 'Name')
        {
            $joinSource['Name'] = $JoinDefinition['Name']
        }

        if ($JoinDefinition.Keys -contains 'Alias')
        {
            $joinSource['Alias'] = $JoinDefinition['Alias']
        }

        if (-not ($joinSource.Keys -contains 'Table' -or $joinSource.Keys -contains 'Name'))
        {
            throw [System.ArgumentException]::new(("Join definitions for view '{0}' must define Table or Name." -f $this.Name))
        }

        if (-not ($JoinDefinition.Keys -contains 'On'))
        {
            throw [System.ArgumentException]::new(("Join definitions for view '{0}' must define On." -f $this.Name))
        }

        return '{0} JOIN {1} ON {2}' -f $joinType.ToUpperInvariant(), $this.FormatSource($joinSource), $this.FormatCondition($JoinDefinition['On'])
    }

    hidden [string] FormatOrderBy([object] $OrderByDefinition)
    {
        if ($OrderByDefinition -is [string])
        {
            return [string] $OrderByDefinition
        }

        if ($OrderByDefinition -isnot [IDictionary])
        {
            throw [System.ArgumentException]::new(("Invalid OrderBy definition for view '{0}'." -f $this.Name))
        }

        $direction = [string] $OrderByDefinition['Direction']
        if (-not $direction)
        {
            $direction = 'ASC'
        }

        return '{0} {1}' -f $this.FormatReference($OrderByDefinition), $direction.ToUpperInvariant()
    }
}
