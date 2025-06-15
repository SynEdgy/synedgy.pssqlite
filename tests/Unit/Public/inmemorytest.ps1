$query = 'CREATE TABLE "characters" (
    "id"    INTEGER,
    "name"    TEXT UNIQUE,
    "guild"    INTEGER,
    "TestNull"    TEXT NULL
);'

$c = New-PSSqliteConnection

# Invoke-PSSqliteQuery -SqliteConnection $c -CommandText "SELECT * FROM characters;" -keepAlive
Invoke-PSSqliteQuery -SqliteConnection $c -CommandText $query -keepAlive
Invoke-PSSqliteQuery -SqliteConnection $c -CommandText "SELECT * FROM characters;" -keepAlive
Invoke-PSSqliteQuery -SqliteConnection $c -CommandText "INSERT INTO characters (id, name, guild) VALUES (1, 'John', 1);" -keepAlive
Invoke-PSSqliteQuery -SqliteConnection $c -CommandText "SELECT * FROM characters;" -keepAlive
Invoke-PSSqliteQuery -SqliteConnection $c -CommandText "SELECT * FROM characters;" -keepAlive -As PSCustomObject
Invoke-PSSqliteQuery -SqliteConnection $c -CommandText "SELECT * FROM characters;" -keepAlive -As OrderedDictionary

$c.Close()


$c = New-PSSqliteConnection -DatabaseFile 'test.sqlite'

# Invoke-PSSqliteQuery -SqliteConnection $c -CommandText "SELECT * FROM characters;" -keepAlive
Invoke-PSSqliteQuery -SqliteConnection $c -CommandText $query -keepAlive
Invoke-PSSqliteQuery -SqliteConnection $c -CommandText "SELECT * FROM characters;" -keepAlive
Invoke-PSSqliteQuery -SqliteConnection $c -CommandText "INSERT INTO characters (id, name, guild) VALUES (1, 'John', 1);" -keepAlive
Invoke-PSSqliteQuery -SqliteConnection $c -CommandText "SELECT * FROM characters;" -keepAlive
# Invoke-PSSqliteQuery -SqliteConnection $c -CommandText "DELETE FROM characters WHERE id = 1;" -keepAlive
