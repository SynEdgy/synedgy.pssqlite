using namespace System.Collections.Generic
using namespace System.Collections

class SqliteIndexConstraint : SqliteConstraint
{
    [bool] $Unique = $false # Indicates if the index is unique
    [bool] $ifNotExists = $true # Indicates if the index is created with IF NOT EXISTS
    [string]$SchemaName # Schema name for the index (optional, default is null)
    [string]$IndexName # Name of the index
    [string]$TableName
    [string[]]$Columns
    [string]$Where # Optional WHERE clause for partial indexes

    SqliteIndexConstraint()
    {
        # Default constructor
    }

    SqliteIndexConstraint([IDictionary]$Definition)
    {
        if (-not [string]::IsNullOrEmpty($Definition.Unique))
        {
            $null = [bool]::TryParse($Definition['Unique'], [ref]$this.Unique)
        }

        if (-not [string]::IsNullOrEmpty($Definition.ifNotExists))
        {
            $null = [bool]::TryParse($Definition['ifNotExists'], [ref]$this.ifNotExists)
        }

        $this.SchemaName = $Definition['SchemaName']
        $this.IndexName = $Definition['IndexName']
        $this.TableName = $Definition['TableName']
        $this.Columns = ($Definition['Columns'] -as [string[]]).Where({ $_ -ne $null }) # Ensure Columns is an array of strings
        if ($Definition.keys -contains 'Where')
        {
            $this.Where = $Definition['Where']
        }

        $this.ValidateDefinition()
    }

    [void] ValidateDefinition()
    {
        if (-not $this.IndexName)
        {
            throw [System.ArgumentException]::new('IndexName is required.')
        }

        if (-not $this.TableName)
        {
            throw [System.ArgumentException]::new('TableName is required.')
        }

        if (-not $this.Columns -or $this.Columns.Count -eq 0)
        {
            throw [System.ArgumentException]::new('At least one column is required for the index.')
        }
    }

    [string] CreateString()
    {
        [System.Text.StringBuilder]$sb = [System.Text.StringBuilder]::new()
        $sb.Append('CREATE {0}INDEX ') -f (if ($this.Unique) { 'UNIQUE ' })
        if ($this.ifNotExists)
        {
            $sb.Append('IF NOT EXISTS ')
        }

        if ($this.SchemaName)
        {
            $sb.Append('{0}.' -f $this.SchemaName)
        }
        $sb.Append('{0} ON {1} (' -f $this.IndexName, $this.TableName)
        if ($this.Columns -and $this.Columns.Count -gt 0)
        {
            $sb.Append(($this.Columns -join ', '))
        }

        $sb.Append(')')
        if ($this.WHERE)
        {
            $sb.Append(' WHERE {0}' -f $this.Where)
        }

        return $sb.ToString()
    }
}
