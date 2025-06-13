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

    SqlitePrimaryKeyTableConstraint([IDictionary]$Definition)
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
        return (
            'CONSTRAINT {0} PRIMARY KEY ({1}){2}' -f $this.Name, ($this.Columns -join ', '), $this.GetConflictClauseString()
        )
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
