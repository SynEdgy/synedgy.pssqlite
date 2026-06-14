class SqliteDBSchema
{
    [SqliteTable[]] $Tables = @()
    [SqliteView[]] $Views = @()
    [SqliteIndexConstraint[]] $Indexes = @()

    SqliteDBSchema()
    {
        # Default constructor
    }

    SqliteDBSchema([IDictionary] $Definition)
    {
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
            (-not $this.Views -or $this.Views.Count -eq 0)
        )
        {
            throw [System.ArgumentException]::new('At least one table or view is required in the schema.')
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

        return $sb.ToString()
    }
}
