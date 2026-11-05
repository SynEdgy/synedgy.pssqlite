using namespace System.Collections.Generic
using namespace System.Collections

class SqlitePrimaryKeyTableConstraint : SqliteConstraint
{
    [string]$Name
    [string[]]$Columns
    [string]$ConflictClause = 'NONE' # Default conflict clause

    SqlitePrimaryKeyTableConstraint() : Base('PrimaryKey')
    {
        # Default constructor
    }

    SqlitePrimaryKeyTableConstraint([IDictionary]$Definition) : Base('PrimaryKey')
    {
        $this.Name = $Definition['Name']
        $this.Columns = ($Definition['Columns'] -as [string[]]).Where({ $_ -ne $null }) # Ensure Columns is an array of strings
        if ($Definition.keys -contains 'ConflictClause')
        {
            $this.ConflictClause = $Definition['ConflictClause']
        }
    }

    [string]ToString()
    {
        $this.ValidateDefinition()
        return (
            '{0}PRIMARY KEY ({1}){2}' -f $(if ($this.Name) { 'CONSTRAINT {0} ' -f $this.Name }), ($this.Columns -join ', '), $this.GetConflictClauseString()
        )
    }

    [void] ValidateDefinition()
    {
        if (-not $this.Columns -or $this.Columns.Count -eq 0)
        {
            throw [ArgumentException]::new('At least one column is required for a primary key.')
        }

        if ($this.ConflictClause -notin @('NONE', 'ROLLBACK', 'ABORT', 'FAIL', 'IGNORE', 'REPLACE'))
        {
            throw [ArgumentException]::new('Invalid primary key conflict clause.')
        }
    }

    [string]GetConflictClauseString()
    {
        if ($this.ConflictClause -and $this.ConflictClause -ne "NONE")
        {
            return " ON CONFLICT {0}" -f $this.ConflictClause
        }
        else
        {
            return ''
        }
    }
}
