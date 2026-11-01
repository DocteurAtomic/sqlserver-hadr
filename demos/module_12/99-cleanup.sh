#!/usr/bin/env bash
# Module 12, cleanup. Gives the lab back as setup/install.sh left it: the database mirroring
# endpoint started again on each instance (clip 12.1 stops the one of hadrlab3); the groups
# AgPacha (clips 12.1 and 12.2), m12_disk (clip 12.3) and AgHealth (the exercise) removed from
# the three instances, whatever the roles they were left in (setup/ag-remove.sh: PachadataTraining
# stays on hadrlab1 alone, online); then, on each instance, the databases of the module
# (m12_...) and of its exercise (ex_health) dropped, with their backup and restore history in
# msdb; the files of clip 12.3 in /dev/shm of hadrlab2 (the copy of m12_disk and the filler);
# the module's folders on the shared volume; and the AlwaysOn_health session as setup/install.sh
# leaves it (clip 12.2 and the exercise start it): stopped, not started with the instance, its
# files deleted. The three instances must be running.
# evidence/ is not touched.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
for n in $nodes; do
    sql $n -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @e sysname = (SELECT name FROM sys.database_mirroring_endpoints WHERE state_desc <> N'STARTED'), @q nvarchar(400);
IF @e IS NOT NULL
BEGIN
    SET @q = N'ALTER ENDPOINT ' + QUOTENAME(@e) + N' STATE = STARTED;';
    EXEC (@q);
    PRINT CONCAT(N'endpoint ', @e, N' started again on ', @@SERVERNAME);
END;
SQL
done
for ag in AgPacha m12_disk AgHealth; do
    bash setup/ag-remove.sh $ag
done
for n in $nodes; do
    sql $n -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @db sysname, @q nvarchar(max);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE name LIKE N'm12[_]%' OR name = N'ex_health';
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
WHERE destination_database_name LIKE N'm12[_]%' OR destination_database_name = N'ex_health';
DELETE msdb.dbo.restorefile WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorefilegroup WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorehistory WHERE restore_history_id IN (SELECT id FROM @ids);
DECLARE h CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT database_name FROM msdb.dbo.backupset
    WHERE database_name LIKE N'm12[_]%' OR database_name = N'ex_health';
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
for n in $nodes; do
    sql $n -h -1 -Q "SET NOCOUNT ON;
IF EXISTS (SELECT * FROM sys.dm_xe_sessions WHERE name = N'AlwaysOn_health')
    ALTER EVENT SESSION AlwaysOn_health ON SERVER STATE = STOP;
ALTER EVENT SESSION AlwaysOn_health ON SERVER WITH (STARTUP_STATE = OFF);"
    $engine exec $n sh -c 'rm -f /var/opt/mssql/log/AlwaysOn_health*.xel'
done
$engine exec hadrlab2 sh -c 'rm -rf /dev/shm/m12'
$engine exec -u 0 hadrlab1 sh -c 'rm -rf /var/opt/mssql/share/m12 /var/opt/mssql/share/ex_health'
echo "Module 12 removed from the lab."
