class SqliteCheckTableConstraint : SqliteConstraint
{
    [string]$Name
    [string]$TableName
    [string]$ColumnName
    [string]$CheckExpression # Expression for CHECK constraints


    SqliteCheckTableConstraint() : Base('Check')
    {
        # Default constructor
    }

    SqliteCheckTableConstraint([System.Collections.IDictionary]$Definition) : Base('Check')
    {
        $this.Name = $Definition['Name']
        $this.TableName = $Definition['TableName']
        $this.ColumnName = $Definition['ColumnName']
        $this.CheckExpression = $Definition['CheckExpression']

        $this.ValidateConstraint()
    }

    [void] ValidateConstraint()
    {
        if (-not $this.CheckExpression)
        {
            throw "CheckExpression is required for CHECK constraints."
        }
    }

    [string] ToString()
    {
        $this.ValidateConstraint() # Ensure the constraint is valid before converting to string
        $prefix = if ($this.Name) { 'CONSTRAINT {0} ' -f $this.Name } else { '' }

        return "{0}CHECK ({1})" -f $prefix, $this.CheckExpression
    }
}
