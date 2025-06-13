class SqliteForeignKeyTableConstraint : SqliteConstraint
{
    [string]$Name
    [string]$TableName
    [string]$ForeignTableName
    [string[]]$Columns
    [string[]]$ForeignColumns
    [string]$OnUpdate
    [string]$OnDelete

    SqliteForeignKeyTableConstraint()
    {
        # Default constructor
    }
}
