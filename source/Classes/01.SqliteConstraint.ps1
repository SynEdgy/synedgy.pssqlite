class SQLiteConstraint
{
    [SqliteConstraintType]$ConstraintType # e.g., 'INDEX', 'FOREIGNKEY', 'PRIMARYKEY', 'CHECK'

    SQLiteConstraint()
    {
        # Default constructor
    }

    SQLiteConstraint([string]$constraintType)
    {
        $this.ConstraintType = $constraintType
    }

    SQLiteConstraint([SqliteConstraintType]$constraintType)
    {
        $this.ConstraintType = $constraintType
    }
}
