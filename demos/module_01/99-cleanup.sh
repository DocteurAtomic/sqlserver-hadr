#!/usr/bin/env bash
# Module 1, cleanup. Gives the lab back as setup/install.sh left it: on the three instances,
# drops the databases of the module (m01_...) and of its exercise (ex_needs), deletes their
# backup and restore history in msdb, and deletes their files from the shared volume
# (/var/opt/mssql/share/m01 and m01_registration-full.bak). PachadataTraining is not
# touched, nor evidence/, which keeps your measures for the last module.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
for n in $nodes; do
    sql $n <<'SQL'
SET NOCOUNT ON;
DECLARE @db sysname, @q nvarchar(max);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE name LIKE N'm01[_]%' OR name = N'ex_needs';
OPEN c;
FETCH c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- A restoring copy cannot be set to SINGLE_USER: it is dropped as it is.
    IF DATABASEPROPERTYEX(@db, 'Status') = N'ONLINE'
    BEGIN
        SET @q = N'ALTER DATABASE ' + QUOTENAME(@db) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
        EXEC (@q);
    END;
    SET @q = N'DROP DATABASE ' + QUOTENAME(@db) + N';';
    EXEC (@q);
    PRINT N'dropped ' + @db + N' on ' + @@SERVERNAME;
    FETCH c INTO @db;
END;
CLOSE c;
DEALLOCATE c;
-- The history outlives the databases: backups of m01_ and ex_ databases, and restores into them.
DECLARE h CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT database_name FROM msdb.dbo.backupset
    WHERE database_name LIKE N'm01[_]%' OR database_name = N'ex_needs'
    UNION
    SELECT DISTINCT destination_database_name FROM msdb.dbo.restorehistory
    WHERE destination_database_name LIKE N'm01[_]%' OR destination_database_name = N'ex_needs';
OPEN h;
FETCH h INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = @db;
    FETCH h INTO @db;
END;
CLOSE h;
DEALLOCATE h;
-- A restore of PachadataTraining's backup into m01_registration points to the backup set of
-- PachadataTraining, which the procedure above keeps: its restore rows go one by one.
DECLARE @ids TABLE (id int PRIMARY KEY);
INSERT @ids SELECT restore_history_id FROM msdb.dbo.restorehistory
WHERE destination_database_name LIKE N'm01[_]%' OR destination_database_name = N'ex_needs';
DELETE msdb.dbo.restorefile WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorefilegroup WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorehistory WHERE restore_history_id IN (SELECT id FROM @ids);
SQL
done
$engine exec -u 0 hadrlab1 rm -rf /var/opt/mssql/share/m01 /var/opt/mssql/share/m01_registration-full.bak
echo "Module 1 removed from the lab."
