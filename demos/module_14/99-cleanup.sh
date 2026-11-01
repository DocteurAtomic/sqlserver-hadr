#!/usr/bin/env bash
# Module 14, cleanup. Gives the lab back as setup/install.sh left it: the distributed group
# DagPacha dropped (DROP AVAILABILITY GROUP, as Learn removes it) on each instance where it has a
# local replica, whatever its role: the primaries of AgSite1 and AgSite2. The secondary of
# AgSite1 also lists DagPacha in sys.availability_groups but refuses the DROP (Msg 15151); the
# name goes away with AgSite1. Then the groups AgSite1
# and AgSite2 removed from the three instances (setup/ag-remove.sh), then the databases of the
# module (m14_...) dropped on the three instances, with their backup and restore history in
# msdb, and their backup files on the shared volume. PachadataTraining is not touched. The
# report of the exercise (exercises/module_14/report.md) and evidence/ are not touched either:
# they are your answer and your measures.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
for n in hadrlab3 hadrlab1 hadrlab2; do
    sql $n -h -1 -Q "SET NOCOUNT ON; IF EXISTS (SELECT * FROM sys.availability_groups AS g
        JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.group_id = g.group_id AND rs.is_local = 1
        WHERE g.name = N'DagPacha')
    BEGIN DROP AVAILABILITY GROUP DagPacha; PRINT CONCAT(N'distributed availability group DagPacha dropped on ', @@SERVERNAME); END;"
done
bash setup/ag-remove.sh AgSite2
bash setup/ag-remove.sh AgSite1
for n in $nodes; do
    sql $n -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @db sysname, @q nvarchar(max);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM sys.databases WHERE name LIKE N'm14[_]%';
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
INSERT @ids SELECT restore_history_id FROM msdb.dbo.restorehistory WHERE destination_database_name LIKE N'm14[_]%';
DELETE msdb.dbo.restorefile WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorefilegroup WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorehistory WHERE restore_history_id IN (SELECT id FROM @ids);
DECLARE h CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT database_name FROM msdb.dbo.backupset WHERE database_name LIKE N'm14[_]%';
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
$engine exec -u 0 hadrlab1 rm -rf /var/opt/mssql/share/m14
echo "Module 14 removed from the lab."
