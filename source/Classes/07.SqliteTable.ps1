class SqliteTable
{
    [string]$Name
    [string]$Schema
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

        if ($Definition.keys -contains 'Columns')
        {
            foreach ($columnName in $Definition['Columns'].keys)
            {
                $currentColumn = $Definition['Columns'][$columnName]
                $currentColumn['Name'] = $columnName
                $column = [SqliteColumn]::new($currentColumn)
                $this.Columns += $column
                # $this.Columns += [SqliteColumn]::new($column)
            }
        }

        if ($Definition.keys -contains 'Strict')
        {
            $this.Strict = $Definition['Strict']
        }

        if ($Definition.keys -contains 'Constraints')
        {
            # foreach ($constraint in $Definition['Constraints'])
            # {
            #     $this.Constraints += [SQLiteConstraint]::new($constraint)
            # }
        }

        if ($Definition.keys -contains 'Options')
        {
            foreach ($option in $Definition['Options'])
            {
                $this.Options = ($option -as [SQLiteTableOption[]])
            }
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

        [int]$i = 0
        for ($i; $i -lt $this.Columns.Count; $i++)
        {
            Write-Verbose -Message ('Adding column {0} to table {1}' -f $this.Columns[$i].Name, $this.Name)
            $null = $sb.Append(('    {0}' -f $this.Columns[$i].ToString()))
            if ($i -lt ($this.Columns.Count - 1))
            {
                # There's more columns to append, and it's not the first one
                $null = $sb.AppendLine(',')
            }
            else
            {
                $null = $sb.AppendLine('')
            }
        }

        $null = $sb.AppendLine(')')

        if ($this.Options.Count -gt 0)
        {
            $null = $sb.Append(' ')
            $null = $sb.Append(($this.Options | ForEach-Object { $_.ToString() }) -join ', ')
        }

        return $sb.ToString()
    }
}
