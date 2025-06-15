using namespace System.Collections.Generic
using namespace System.Collections

class SqliteIndexConstraint : SqliteConstraint
{
    [string]$Name # Name of the index
    [string]$Table # Name of the table on which the index is created
    [bool] $Unique = $false # Indicates if the index is unique
    [bool] $ifNotExists = $true # Indicates if the index is created with IF NOT EXISTS
    [string]$SchemaName # Schema name for the index (optional, default is null)
    [string[]]$Columns
    [string]$Where # Optional WHERE clause for partial indexes

    SqliteIndexConstraint()
    {
        # Default constructor
    }

    SqliteIndexConstraint([IDictionary]$Definition)
    {
        $this.Name = $Definition['Name']

        if (-not [string]::IsNullOrEmpty($Definition.Unique))
        {
            [bool]$refValue = $this.Unique
            $null = [bool]::TryParse($Definition['Unique'], [ref]$refValue)
            $this.Unique = $refValue
        }

        if (-not [string]::IsNullOrEmpty($Definition.ifNotExists))
        {
            $null = [bool]::TryParse($Definition['ifNotExists'], [ref]$this.ifNotExists)
        }

        $this.SchemaName = $Definition['SchemaName']
        $this.Table = $Definition['Table']
        $this.Columns = ($Definition['Columns'] -as [string[]]).Where({ $_ -ne $null }) # Ensure Columns is an array of strings
        if ($Definition.keys -contains 'Where')
        {
            $this.Where = $Definition['Where']
        }

        $this.ValidateDefinition()
    }

    [void] ValidateDefinition()
    {
        if (-not $this.Name)
        {
            throw [System.ArgumentException]::new('Name is required for an index.')
        }

        if (-not $this.Table)
        {
            throw [System.ArgumentException]::new('The Table''s name is required.')
        }

        if (-not $this.Columns -or $this.Columns.Count -eq 0)
        {
            throw [System.ArgumentException]::new('At least one column is required for the index.')
        }
    }

    [string] CreateString()
    {
        [System.Text.StringBuilder]$sb = [System.Text.StringBuilder]::new()
        $sb.Append('CREATE')
        if ($this.Unique)
        {
            $sb.Append(' UNIQUE')
        }

        $sb.Append(' INDEX ')

        if ($this.ifNotExists)
        {
            $sb.Append('IF NOT EXISTS ')
        }

        if ($this.SchemaName)
        {
            $sb.Append('{0}.' -f $this.SchemaName)
        }

        $sb.Append(('{0} ON {1}(' -f $this.Name, $this.Table))

        if ($this.Columns -and $this.Columns.Count -gt 0)
        {
            $sb.Append(($this.Columns -join ', '))
        }

        $sb.Append(')')
        if ($this.WHERE)
        {
            $sb.Append((' WHERE {0}' -f $this.Where))
        }

        $sb.AppendLine(';')

        return $sb.ToString()
    }
}
