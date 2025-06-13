class SqliteCheckTableConstraint : SqliteConstraint
{
    [string]$TableName
    [string]$ColumnName
    [string]$CheckExpression # Expression for CHECK constraints


    SqliteCheckTableConstraint() : Base('INDEX')
    {
        # Default constructor
    }

    SqliteCheckTableConstraint([System.Collections.IDictionary]$Definition) : Base('INDEX')
    {
        $this.TableName = $Definition['TableName']
        $this.ColumnName = $Definition['ColumnName']
        $this.CheckExpression = $Definition['CheckExpression']

        $this.ValidateConstraint()
    }

    [void] ValidateConstraint()
    {
        if (-not $this.TableName)
        {
            throw "TableName is required for CHECK constraints."
        }

        if (-not $this.CheckExpression)
        {
            throw "CheckExpression is required for CHECK constraints."
        }
    }

    [string] ToString()
    {
        $this.ValidateConstraint() # Ensure the constraint is valid before converting to string
        return "CONSTRAINT {0} CHECK ({1})" -f $this.Name, $this.CheckExpression
    }
}
