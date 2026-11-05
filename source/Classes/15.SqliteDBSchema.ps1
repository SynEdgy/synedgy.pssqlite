class SqliteDBSchema
{
    [SqliteTable[]] $Tables = @()
    [SqliteView[]] $Views = @()
    [SqliteIndexConstraint[]] $Indexes = @()
    [System.Collections.IDictionary[]] $SetupSql = @()

    SqliteDBSchema()
    {
        # Default constructor
    }

    SqliteDBSchema([IDictionary] $Definition)
    {
        foreach ($key in $Definition.Keys)
        {
            if ($key -notin @('Tables', 'Views', 'Indexes', 'SetupSql'))
            {
                throw [System.ArgumentException]::new("Unknown schema configuration key '$key'.")
            }
        }

        if ($Definition.Keys -contains 'SetupSql')
        {
            foreach ($statement in $Definition['SetupSql'])
            {
                if ($statement -isnot [System.Collections.IDictionary] -or
                    [string]::IsNullOrWhiteSpace($statement['Name']) -or
                    [string]::IsNullOrWhiteSpace($statement['Sql']))
                {
                    throw [System.ArgumentException]::new('Each SetupSql entry requires a Name and Sql string.')
                }

                foreach ($key in $statement.Keys)
                {
                    if ($key -notin @('Name', 'Sql')) { throw [System.ArgumentException]::new("Unknown SetupSql key '$key'.") }
                }

                $this.SetupSql += $statement
            }
        }

        if ($Definition.Keys -contains 'Tables')
        {
            foreach ($tableName in $Definition['Tables'].Keys)
            {
                $currentTable = $Definition['Tables'][$tableName]
                $currentTable['Name'] = $tableName
                $this.Tables += [SqliteTable]::new($currentTable)
            }
        }

        if ($Definition.Keys -contains 'Views')
        {
            foreach ($viewName in $Definition['Views'].Keys)
            {
                $currentView = $Definition['Views'][$viewName]
                $currentView['Name'] = $viewName
                $this.Views += [SqliteView]::new($currentView)
            }
        }

        if ($Definition.Keys -contains 'Indexes')
        {
            foreach ($indexName in $Definition['Indexes'].Keys)
            {
                $currentIndex = $Definition['Indexes'][$indexName]
                $currentIndex['Name'] = $indexName
                $this.Indexes += [SqliteIndexConstraint]::new($currentIndex)
            }
        }
    }

    [void] ValidateDefinition()
    {
        if (
            (-not $this.Tables -or $this.Tables.Count -eq 0) -and
            (-not $this.Views -or $this.Views.Count -eq 0) -and
            (-not $this.SetupSql -or $this.SetupSql.Count -eq 0)
        )
        {
            throw [System.ArgumentException]::new('At least one table, view or setup statement is required in the schema.')
        }

        foreach ($table in $this.Tables)
        {
            $table.ValidateDefinition()
        }

        foreach ($view in $this.Views)
        {
            $view.ValidateDefinition()
        }

        $relationNames = @($this.Tables.Name) + @($this.Views.Name)
        $duplicateNames = $relationNames |
            Group-Object -CaseSensitive:$false |
            Where-Object Count -gt 1

        if ($duplicateNames)
        {
            throw [System.ArgumentException]::new(("Table and view names must be unique. Duplicate names: {0}" -f ($duplicateNames.Name -join ', ')))
        }

        if ($this.Indexes)
        {
            foreach ($index in $this.Indexes)
            {
                $index.ValidateDefinition()
            }
        }

        $setupNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($statement in $this.SetupSql)
        {
            if ([string]::IsNullOrWhiteSpace($statement['Name']) -or
                [string]::IsNullOrWhiteSpace($statement['Sql']) -or
                -not $setupNames.Add($statement['Name']))
            {
                throw [System.ArgumentException]::new('SetupSql entries must have SQL and unique non-empty names.')
            }
        }
    }

    [SqliteTable] GetTable([string] $Name)
    {
        $tableDefinition = @($this.Tables.Where{ $_.Name -ieq $Name })[0]
        return $tableDefinition
    }

    [SqliteView] GetView([string] $Name)
    {
        $viewDefinition = @($this.Views.Where{ $_.Name -ieq $Name })[0]
        return $viewDefinition
    }

    [object] GetSelectable([string] $Name)
    {
        $tableDefinition = $this.GetTable($Name)
        if ($tableDefinition)
        {
            return $tableDefinition
        }

        return $this.GetView($Name)
    }

    [string] GetSchemaSDL()
    {
        $this.ValidateDefinition()
        [System.Text.StringBuilder]$sb = [System.Text.StringBuilder]::new()

        foreach ($table in $this.Tables)
        {
            $sb.AppendLine($table.CreateString())
        }

        foreach ($view in $this.Views)
        {
            $sb.AppendLine($view.CreateString())
        }

        foreach ($index in $this.Indexes)
        {
            $sb.AppendLine($index.CreateString())
        }

        foreach ($table in $this.Tables)
        {
            $null = $sb.AppendLine($table.GetIndexSDL())
        }

        return $sb.ToString()
    }
}
