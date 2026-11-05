class SqliteTable
{
    [string]$Name
    [string]$Schema
    [bool] $ifNotExists = $true # If true, the table will only be created if it does not already exist
    [SqliteColumn[]]$Columns
    [SQLiteConstraint[]]$Constraints = @() # List of constraints for the table
    [SQLiteTableOption[]]$Options = @() # Options for the table, such as WithoutRowId or Strict

    SqliteTable()
    {
        # Default constructor
    }

    SqliteTable([System.Collections.IDictionary]$Definition)
    {
        $this.Name = $Definition['Name']

        if ($Definition.Keys -contains 'Schema')
        {
            $this.Schema = $Definition['Schema']
        }

        if ($Definition.Keys -contains 'IfNotExists')
        {
            $this.ifNotExists = [bool]$Definition['IfNotExists']
        }

        if ($Definition.keys -contains 'Columns')
        {
            foreach ($columnName in $Definition['Columns'].keys)
            {
                $currentColumn = $Definition['Columns'][$columnName]
                $currentColumn['Name'] = $columnName
                $this.Columns += [SqliteColumn]::new($currentColumn)
            }
        }

        if ($Definition.keys -contains 'Strict')
        {
            $this.Strict = $Definition['Strict']
        }

        if ($Definition.keys -contains 'Constraints')
        {

            foreach ($constraint in $Definition['Constraints'])
            {
                $constraint['Table'] = $this.Name # Ensure the constraint has the table name set
                switch ($constraint['Type'])
                {
                    'ForeignKey'
                    {
                        $this.Constraints += [SqliteForeignKeyTableConstraint]::new($constraint)
                    }

                    'Check'
                    {
                        $this.Constraints += [SqliteCheckTableConstraint]::new($constraint)
                    }

                    'PrimaryKey'
                    {
                        $this.Constraints += [SqlitePrimaryKeyTableConstraint]::new($constraint)
                    }

                    'Index'
                    {
                        $this.Constraints += [SqliteIndexConstraint]::new($constraint)
                    }

                    default
                    {
                        throw [System.ArgumentException]::new(('Unknown constraint type {0} for table {1}.' -f $constraint['Type'], $this.Name))
                    }
                }
            }
        }

        if ($Definition.keys -contains 'Options')
        {
            $this.Options = $Definition['Options'] -as [SQLiteTableOption[]]
        }
    }

    [void] ValidateDefinition()
    {
        if (-not $this.Name)
        {
            throw [System.ArgumentException]::new('Table Name is required.')
        }

        if ($this.Columns.Count -eq 0)
        {
            throw [System.ArgumentException]::new('At least one column is required in the table definition.')
        }

        foreach ($column in $this.Columns)
        {
            $column.ValidateDefinition()
        }

        $primaryKeyCount = @($this.Columns | Where-Object PrimaryKey).Count
        foreach ($constraint in $this.Constraints)
        {
            if ($constraint -is [SqliteCheckTableConstraint])
            {
                $constraint.ValidateConstraint()
            }
            else
            {
                $constraint.ValidateDefinition()
                foreach ($columnName in $constraint.Columns)
                {
                    if ($columnName -notin $this.Columns.Name)
                    {
                        throw [System.ArgumentException]::new("Constraint references unknown column '$columnName' in table '$($this.Name)'.")
                    }
                }
            }

            if ($constraint -is [SqlitePrimaryKeyTableConstraint]) { $primaryKeyCount++ }
        }

        if ($primaryKeyCount -gt 1)
        {
            throw [System.ArgumentException]::new("Table '$($this.Name)' has more than one primary key; use a single composite constraint.")
        }
    }

    [string] CreateString()
    {
        $this.ValidateDefinition()
        # Generate the CREATE TABLE statement
        # https://sqlite.org/syntax/create-table-stmt.html
        [System.Text.StringBuilder]$sb = [System.Text.StringBuilder]::new()
        $null = $sb.Append('CREATE')
        if ($this.Temporary)
        {
            $null = $sb.Append(' TEMPORARY')
        }

        $null = $sb.Append(' TABLE')

        if ($this.ifNotExists)
        {
            $null = $sb.Append(' IF NOT EXISTS ')
        }

        if ($this.Schema)
        {
            $null = $sb.Append(('{0}.' -f $this.Schema))
        }

        # Append the table name
        $null = $sb.Append((' {0}' -f $this.Name))
        # AS Select Statement goes here (not supported in this class yet)

        # Append the columns
        $null = $sb.AppendLine(' (')

        $definitions = [System.Collections.Generic.List[string]]::new()
        foreach ($column in $this.Columns)
        {
            $definitions.Add('    ' + $column.ToString())
        }

        foreach ($constraint in $this.Constraints)
        {
            if ($constraint -isnot [SqliteIndexConstraint])
            {
                $definitions.Add('    ' + $constraint.ToString())
            }
        }

        $null = $sb.AppendLine(($definitions -join (',' + [Environment]::NewLine)))

        $null = $sb.Append(')')

        if ($this.Options.Count -gt 0)
        {
            $null = $sb.Append(' ')
            $null = $sb.Append(($this.Options | ForEach-Object { if ($_ -eq [SQLiteTableOption]::WithoutRowId) { 'WITHOUT ROWID' } else { $_.ToString().ToUpperInvariant() } }) -join ', ')
        }

        $sb.AppendLine(';')
        return $sb.ToString()
    }

    [string] GetIndexSDL()
    {
        $this.ValidateDefinition()
        $sb = [System.Text.StringBuilder]::new()
        foreach ($constraint in $this.Constraints)
        {
            if ($constraint -is [SqliteIndexConstraint])
            {
                $null = $sb.AppendLine($constraint.CreateString())
            }
        }

        return $sb.ToString()
    }
}
