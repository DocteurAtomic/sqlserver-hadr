#!/usr/bin/env bash
# Module 6, cleanup. Gives the lab back as setup/install.sh left it, which is also how module 5
# leaves it: the groups AgPacha (the demos) and AgBascule (the exercise) removed from the three
# instances, whatever the roles a failover left them in, with their listener (setup/ag-remove.sh:
# PachadataTraining stays on hadrlab1 alone, online, in the full recovery model), then the
# databases of the module (m06_...) and of its exercise (ex_bascule) dropped on the three
# instances, with their backup and restore history in msdb, and their backup files on the
# shared volume. The three instances must be running: after 05-forced.sh, run
# 06-two-primaries.sh, which starts hadrlab1 again. evidence/ is not touched.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash setup/ag-remove.sh AgPacha
bash setup/ag-remove.sh AgBascule
for n in $nodes; do
    sql $n -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @db sysname, @q nvarchar(max);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE name LIKE N'm06[_]%' OR name = N'ex_bascule';
OPEN c;
FETCH c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF DATABASEPROPERTYEX(@db, 'Status') = N'ONLINE'
       AND DATABASEPROPERTYEX(@db, 'Updateability') = N'READ_WRITE'
    BEGIN
        SET @q = N'ALTER DATABASE ' + QUOTENAME(@db) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
        EXEC (@q);
    END;
    SET @q = N'DROP DATABASE ' + QUOTENAME(@db) + N';';
    EXEC (@q);
    PRINT CONCAT(N'dropped ', @db, N' on ', @@SERVERNAME);
    FETCH c INTO @db;
END;
CLOSE c;
DEALLOCATE c;
DECLARE @ids TABLE (id int PRIMARY KEY);
INSERT @ids SELECT restore_history_id FROM msdb.dbo.restorehistory
WHERE destination_database_name LIKE N'm06[_]%' OR destination_database_name = N'ex_bascule';
DELETE msdb.dbo.restorefile WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorefilegroup WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorehistory WHERE restore_history_id IN (SELECT id FROM @ids);
DECLARE h CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT database_name FROM msdb.dbo.backupset
    WHERE database_name LIKE N'm06[_]%' OR database_name = N'ex_bascule';
OPEN h;
FETCH h INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = @db;
    FETCH h INTO @db;
END;
CLOSE h;
DEALLOCATE h;
SQL
done
$engine exec -u 0 hadrlab1 sh -c 'rm -rf /var/opt/mssql/share/m06 /var/opt/mssql/share/ex_bascule'
echo "Module 6 removed from the lab."
