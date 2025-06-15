enum DBMigrationMode
{
    INCREMENTAL # Assume the database already exists and only apply changes "IF NOT EXISTS"
    CREATE      # Only create a new database if it doesn't exist, dropping any existing tables
    OVERWRITE   # remove the db file and create a new one
}
