$query = 'CREATE TABLE "characters" (
    "id"    INTEGER,
    "name"    TEXT UNIQUE,
    "guild"    INTEGER
);'

$c = New-PSSqliteConnection

# Invoke-PSSqliteQuery -SqliteConnection $c -Query "SELECT * FROM characters;" -keepAlive
Invoke-PSSqliteQuery -SqliteConnection $c -Query $query -keepAlive
Invoke-PSSqliteQuery -SqliteConnection $c -Query "SELECT * FROM characters;" -keepAlive
Invoke-PSSqliteQuery -SqliteConnection $c -Query "INSERT INTO characters (id, name, guild) VALUES (1, 'John', 1);" -keepAlive
Invoke-PSSqliteQuery -SqliteConnection $c -Query "SELECT * FROM characters;" -keepAlive
Invoke-PSSqliteQuery -SqliteConnection $c -Query "DELETE FROM characters WHERE id = 1;" -keepAlive
