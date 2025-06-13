class SqliteDBSchema
{
    [SqliteTable[]] $Tables = @()
    # [SqliteView[]] $Views
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
        if (-not $this.Tables -or $this.Tables.Count -eq 0)
        {
            throw [System.ArgumentException]::new('At least one table is required in the schema.')
        }

        foreach ($table in $this.Tables)
        {
            $table.ValidateDefinition()
        }

        if ($this.Indexes)
        {
            foreach ($index in $this.Indexes)
            {
                $index.ValidateDefinition()
            }
        }
    }

}
