using namespace System.Collections

class SqliteViewColumn
{
    [string]$Name
    [string]$Table
    [string]$Column
    [string]$Expression

    SqliteViewColumn()
    {
        # Default constructor
    }

    SqliteViewColumn([IDictionary] $Definition)
    {
        $this.Name = $Definition['Name']

        if ($Definition.Keys -contains 'Expression')
        {
            $this.Expression = [string] $Definition['Expression']
        }

        if ($Definition.Keys -contains 'Source' -and $Definition['Source'] -is [IDictionary])
        {
            $sourceDefinition = $Definition['Source']
            if ($sourceDefinition.Keys -contains 'Table')
            {
                $this.Table = [string] $sourceDefinition['Table']
            }

            if ($sourceDefinition.Keys -contains 'Column')
            {
                $this.Column = [string] $sourceDefinition['Column']
            }

            if ($sourceDefinition.Keys -contains 'Expression')
            {
                $this.Expression = [string] $sourceDefinition['Expression']
            }
        }
        else
        {
            if ($Definition.Keys -contains 'Table')
            {
                $this.Table = [string] $Definition['Table']
            }

            if ($Definition.Keys -contains 'Column')
            {
                $this.Column = [string] $Definition['Column']
            }
        }

        $this.ValidateDefinition()
    }

    [void] ValidateDefinition()
    {
        if (-not $this.Name)
        {
            throw [System.ArgumentException]::new('View column Name is required.')
        }
    }

    [bool] HasSelectExpression()
    {
        return (
            -not [string]::IsNullOrWhiteSpace($this.Expression) -or
            -not [string]::IsNullOrWhiteSpace($this.Column)
        )
    }

    [string] GetSelectExpression()
    {
        if (-not [string]::IsNullOrWhiteSpace($this.Expression))
        {
            return $this.Expression
        }

        if (-not [string]::IsNullOrWhiteSpace($this.Column))
        {
            if (-not [string]::IsNullOrWhiteSpace($this.Table))
            {
                return '{0}.{1}' -f $this.Table, $this.Column
            }

            return $this.Column
        }

        throw [System.ArgumentException]::new(("View column '{0}' must define Expression or Source.Column for structured views." -f $this.Name))
    }

    [string] ToSelectString()
    {
        return '{0} AS {1}' -f $this.GetSelectExpression(), $this.Name
    }
}
