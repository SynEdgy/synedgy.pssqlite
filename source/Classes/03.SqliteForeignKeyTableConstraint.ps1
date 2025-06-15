class SqliteForeignKeyTableConstraint : SqliteConstraint
{
    [string]$Name
    [string]$Table
    [string[]]$Columns
    [string]$ForeignTable
    [string[]]$ForeignColumns
    [string]$OnUpdate
    [string]$OnDelete
    [string]$Match = 'NONE' # Default match type is NONE

    SqliteForeignKeyTableConstraint() : Base('ForeignKey')
    {
        # Default constructor
    }

    SqliteForeignKeyTableConstraint([System.Collections.IDictionary]$Definition) : Base('ForeignKey')
    {
        $this.Name = $Definition['Name']
        $this.Table = $Definition['Table']
        $this.Columns = $Definition['Columns'] -as [string[]]
        $this.ForeignTable = $Definition['ForeignTable']
        $this.ForeignColumns = $Definition['ForeignColumns'] -as [string[]]

        if ($Definition.Keys -contains 'OnUpdate')
        {
            $this.OnUpdate = $Definition['OnUpdate']
        }

        if ($Definition.Keys -contains 'OnDelete')
        {
            $this.OnDelete = $Definition['OnDelete']
        }

        if ($Definition.Keys -contains 'Match')
        {
            $this.Match = $Definition['Match']
        }

        $this.ValidateDefinition()
    }

    [void] ValidateDefinition()
    {
        if (-not $this.Name)
        {
            throw [System.ArgumentException]::new('Name is required for foreign key constraint.')
        }

        if (-not $this.Table)
        {
            throw [System.ArgumentException]::new('Table is required for foreign key constraint.')
        }

        if (-not $this.ForeignTable)
        {
            throw [System.ArgumentException]::new('ForeignTable is required for foreign key constraint.')
        }

        if (-not $this.Columns -or $this.Columns.Count -eq 0)
        {
            throw [System.ArgumentException]::new('At least one column is required for foreign key constraint.')
        }

        if (-not $this.ForeignColumns -or $this.ForeignColumns.Count -eq 0)
        {
            throw [System.ArgumentException]::new('At least one foreign column is required for foreign key constraint.')
        }
    }

    [string] ToString()
    {
        $this.ValidateDefinition()
        # Generate the SQL representation of the foreign key constraint
        # https://sqlite.org/syntax/table-constraint.html
        # https://sqlite.org/syntax/foreign-key-clause.html
        [System.Text.StringBuilder]$sb = [System.Text.StringBuilder]::new()
        $null = $sb.AppendLine(('CONSTRAINT {0} FOREIGN KEY (' -f $this.Name))
        $null = $sb.Append(('    {0}' -f ($this.Columns -join ', ')))
        $null = $sb.AppendLine(') REFERENCES')
        $null = $sb.Append(('    {0} (' -f $this.ForeignTable))

        $null = $sb.Append(('    {0})' -f ($this.ForeignColumns -join ', ')))
        if (-not [string]::IsNullOrEmpty($this.OnUpdate) -or -not [string]::IsNullOrEmpty($this.OnDelete))
        {
            if (-not [string]::IsNullOrEmpty($this.OnUpdate))
            {
                $null = $sb.AppendLine((' ON UPDATE {0}' -f $this.OnUpdate.ToUpper()))
            }

            if (-not [string]::IsNullOrEmpty($this.OnDelete))
            {
                $null = $sb.AppendLine((' ON DELETE {0}' -f $this.OnDelete.ToUpper()))
            }
        }

        # Add MATCH clause if needed
        if ($this.Match -and $this.Match -ne 'NONE')
        {
            $null = $sb.AppendLine((' MATCH {0}' -f $this.Match.ToUpper()))
        }

        $null = $sb.AppendLine(');')

        return $sb.ToString()
    }
}
