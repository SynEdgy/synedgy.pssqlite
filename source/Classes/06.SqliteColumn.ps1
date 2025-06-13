using namespace Microsoft.Data.Sqlite
using namespace System.Collections.Generic
using namespace System.Collections

class SQLiteColumn
{
    # In SQLite, PRIMARY KEY that are INTEGER are automatically indexed and auto-incremented (alias for ROWID)
    [string]$Name
    [SqliteType]$Type # SQLite data type

    #region PK Constraint
    [bool]$PrimaryKey = $false # Primary key column
    [System.Nullable[SqliteOrdering]]$PrimaryKeyOrder = $null # Order of the primary key (ASC or DESC)
    [bool]$AutoIncrement # Auto-incremented column (only for INTEGER PRIMARY KEY)
    #endregion

    [bool]$AllowNull = $true # Allow NULL values (if false, NOT NULL constraint is applied)

    [bool]$Unique = $false # Unique constraint
    [string]$UniqueConflictClause # Conflict clause for unique constraint (e.g., REPLACE, IGNORE)
    [string]$CheckExpression # Check constraint expression (for validation on write operations)
    [object]$DefaultValue # Default value for the column (can be a string, number, or expression). Default is null
    [string]$Collation # Collation for the column (e.g., BINARY, NOCASE, RTRIM)
    [bool]$Indexed = $false # Indexed column
    [string]$References # Foreign key reference (otherwise use a TableConstraint)

    SQLiteColumn()
    {
        # Default constructor
    }

    SQLiteColumn([IDictionary] $Definition)
    {
        $this.Name = $Definition['Name']
        $this.Type = $Definition['Type']
        # $null = [bool]::TryParse($Definition['PrimaryKey'], [ref]$this.PrimaryKey)
        # $this.PrimaryKeyOrder = $Definition['PrimaryKeyOrder']

        if ($Definition.Keys -contains 'PrimaryKey' -and -not [string]::IsNullOrEmpty($Definition['PrimaryKey']))
        {
            # TryParse to handle cases where PrimaryKey is not a boolean
            [bool]$refValue = $this.PrimaryKey
            $null = [bool]::TryParse($Definition['PrimaryKey'], [ref]$refValue)
            $this.PrimaryKey = $refValue
            if ($this.PrimaryKeyOrder -and $this.PrimaryKeyOrder -ne [SqliteOrdering]::None)
            {
                # Ensure PrimaryKeyOrder is set to None if PrimaryKey is false
                $this.PrimaryKeyOrder = 'NONE'
            }
        }

        if ($Definition.Keys -contains 'AutoIncrement' -and -not [string]::IsNullOrEmpty($this.AutoIncrement) -and $this.Type -eq [SqliteType]::Integer)
        {
            Write-Warning -Message ('AutoIncrement is only applicable to INTEGER PRIMARY KEY columns. Setting AutoIncrement to false for column {0}.' -f $this.Name)
            [bool]$refValue = $this.AutoIncrement
            $null = [bool]::TryParse($Definition['AutoIncrement'], [ref]$refValue)
            $this.AutoIncrement = $refValue
        }

        if ($Definition.keys -contains 'AllowNull' -and -not [string]::IsNullOrEmpty($Definition['AllowNull']))
        {
            # TryParse to handle cases where AllowNull is not a boolean
            [bool]$refValue = $this.AllowNull
            $null = [bool]::TryParse($Definition['AllowNull'], [ref]$refValue)
            $this.AllowNull = $refValue
        }

        if ($Definition.Keys -contains 'Unique' -and -not [string]::IsNullOrEmpty($Definition['Unique']))
        {
            # TryParse to handle cases where Unique is not a boolean
            [bool]$refValue = $this.Unique
            $result = [bool]::TryParse($Definition['Unique'], [ref]$refValue)
            $this.Unique = $refValue
            # Log the conversion result
            Write-Debug -Message (
                'Unique constraint for column {0} set to {1} should be {2} (conversion success: {3})' -f $this.Name, $this.Unique, $Definition['Unique'], $result
                )
        }

        if ($Definition.Keys -contains 'UniqueConflictClause' -and -not [string]::IsNullOrEmpty($Definition['UniqueConflictClause']))
        {
            $this.UniqueConflictClause = $Definition['UniqueConflictClause']
        }

        if ($Definition.Keys -contains 'DefaultValue' -and -not [string]::IsNullOrEmpty($Definition['DefaultValue']))
        {
            $this.DefaultValue = $Definition['DefaultValue']
        }

        if ($Definition.Keys -contains 'Collation' -and -not [string]::IsNullOrEmpty($Definition['Collation']))
        {
            $this.Collation = $Definition['Collation']
        }

        if ($Definition.Keys -contains 'References' -and -not [string]::IsNullOrEmpty($Definition['References']))
        {
            $this.References = $Definition['References']
        }

        if ($Definition.Keys -contains 'CheckExpression' -and -not [string]::IsNullOrEmpty($Definition['CheckExpression']))
        {
            $this.CheckExpression = $Definition['CheckExpression']
        }
    }

    [void] ValidateDefinition()
    {
        if (-not $this.Name)
        {
            throw [System.ArgumentException]::new('Column Name is required.')
        }

        if (-not $this.Type)
        {
            throw [System.ArgumentException]::new('Column Type is required.')
        }

        if ($this.PrimaryKey -and $this.AllowNull)
        {
            Write-Warning -Message ('Although SQLite allows this, we recommend that Primary key columns do not allow NULL values.')
        }
    }

    [string] ToString()
    {
        $this.ValidateDefinition()
        # Generate the column definition string
        # https://sqlite.org/syntax/column-def.html
        [System.Text.StringBuilder]$sb = [System.Text.StringBuilder]::new()
        $null = $sb.Append(('{0} {1}' -f $this.Name, $this.Type.ToString().ToUpper()))

        #region Column Constraints
        # https://sqlite.org/syntax/column-constraint.html
        if ($this.PrimaryKey)
        {
            $null = $sb.Append(' PRIMARY KEY')
            if ($this.PrimaryKeyOrder -and $this.PrimaryKeyOrder -ne [SqliteOrdering]::None)
            {
                # Append the order of the primary key if specified
                $null = $sb.Append((' {0}' -f $this.PrimaryKeyOrder.ToString().ToUpper()))
            }

            if ($this.AutoIncrement -or $this.Type -eq [SqliteType]::Integer)
            {
                # If the column is an INTEGER PRIMARY KEY, it is auto-incremented by default (alias for ROWID)
                $null = $sb.Append(' AUTOINCREMENT')
            }
        }
        elseif (-not $this.AllowNull)
        {
            $null = $sb.Append(' NOT NULL')
        }
        elseif ($this.Unique)
        {
            $null = $sb.Append(' UNIQUE')
            if ($this.UniqueConflictClause)
            {
                $null = $sb.Append((' ON CONFLICT {0}' -f $this.UniqueConflictClause))
            }
        }
        elseif (-not [string]::IsNullOrEmpty($this.CheckExpression))
        {
            $null = $sb.Append((' CHECK ({0})' -f $this.CheckExpression))
        }
        elseif (-not [string]::IsNullOrEmpty($this.DefaultValue))
        {
            if ($this.DefaultValue -is [string])
            {
                $useDefaultValue = $this.DefaultValue.Replace("'", "''") # Escape single quotes in string literals
            }
            else
            {
                $useDefaultValue = $this.DefaultValue
            }

            $null = $sb.Append((' DEFAULT {0}' -f $useDefaultValue))
        }
        elseif ($this.Collation)
        {
            $null = $sb.Append((' COLLATE {0}' -f $this.Collation))
        }
        elseif ($this.References)
        {
            $definition += " REFERENCES $($this.References)"
        }
        #endregion

        return $sb.ToString()
    }
}
