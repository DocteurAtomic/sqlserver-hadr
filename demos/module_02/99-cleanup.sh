#!/usr/bin/env bash
# Module 2, cleanup. Gives the lab back as setup/install.sh left it: on the three instances,
# removes the log shipping of the databases of the module (m02_...) and of its exercise
# (ex_logship), with their jobs and the alert job when nothing is left
# (setup/logship-remove.sql), drops these databases, deletes their backup and restore
# history in msdb, and deletes their files: the log backups on the shared volume, the copies
# on the disk of each instance. PachadataTraining is not touched, nor evidence/.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
for n in $nodes; do
    sql $n -v DB='m02[_]%' < setup/logship-remove.sql
    sql $n -v DB='ex[_]logship' < setup/logship-remove.sql
    sql $n <<'SQL'
SET NOCOUNT ON;
DECLARE @db sysname, @q nvarchar(max);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE name LIKE N'm02[_]%' OR name = N'ex_logship';
OPEN c;
FETCH c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- A copy in RESTORING or in STANDBY cannot be set to SINGLE_USER: it is dropped as it is.
    IF DATABASEPROPERTYEX(@db, 'Status') = N'ONLINE' AND DATABASEPROPERTYEX(@db, 'IsInStandBy') = 0
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
DECLARE h CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT database_name FROM msdb.dbo.backupset
    WHERE database_name LIKE N'm02[_]%' OR database_name = N'ex_logship'
    UNION
    SELECT DISTINCT destination_database_name FROM msdb.dbo.restorehistory
    WHERE destination_database_name LIKE N'm02[_]%' OR destination_database_name = N'ex_logship';
OPEN h;
FETCH h INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = @db;
    FETCH h INTO @db;
END;
CLOSE h;
DEALLOCATE h;
-- A restore of PachadataTraining's backup into m02_registration points to the backup set of
-- PachadataTraining, which the procedure above keeps: its restore rows go one by one.
DECLARE @ids TABLE (id int PRIMARY KEY);
INSERT @ids SELECT restore_history_id FROM msdb.dbo.restorehistory
WHERE destination_database_name LIKE N'm02[_]%' OR destination_database_name = N'ex_logship';
DELETE msdb.dbo.restorefile WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorefilegroup WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorehistory WHERE restore_history_id IN (SELECT id FROM @ids);
SQL
    # The undo files of STANDBY stay in the data folder after the database is dropped.
    $engine exec -u 0 $n sh -c 'rm -rf /var/opt/mssql/logship-copy;
        rm -f /var/opt/mssql/data/m02_*.tuf /var/opt/mssql/data/ex_logship_*.tuf'
done
$engine exec -u 0 hadrlab1 sh -c 'rm -rf /var/opt/mssql/share/logship/m02_registration \
    /var/opt/mssql/share/logship/ex_logship /var/opt/mssql/share/logship/m02_registration_tail*.trn \
    /var/opt/mssql/share/logship/ex_logship_tail*.trn /var/opt/mssql/share/m02_registration-full.bak \
    /var/opt/mssql/share/ex_logship'
echo "Module 2 removed from the lab."
