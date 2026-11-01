#!/usr/bin/env bash
# Removes an availability group from the three instances, whatever their roles: the
# secondaries first, then the primary (dropped on the primary first, the group takes 10 to
# 20 seconds more to leave each secondary). On each instance: DROP AVAILABILITY GROUP, then the copies the group leaves in
# RESTORING are dropped; PachadataTraining is dropped everywhere except on hadrlab1, where it
# stays online, outside any group. The databases that stay online (the primary's) are kept:
# the cleanup of a module drops its own. Also deletes, in msdb, the history that the
# automatic seeding wrote for PachadataTraining (on hadrlab1, its backups to a GUID device;
# elsewhere, its whole history). Does nothing on an instance without the group.
# Added by module 3. Usage: ./setup/ag-remove.sh AgPacha     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/.."
. setup/lib.sh
ag=${1:?usage: setup/ag-remove.sh <availability group>}
for pass in secondaries primary; do
  for n in $nodes; do
    sql $n -h -1 -v AG="$ag" PASS="$pass" <<'SQL'
SET NOCOUNT ON;
DECLARE @ag sysname = N'$(AG)', @db sysname, @q nvarchar(max);
DECLARE @dbs TABLE (name sysname PRIMARY KEY);
-- First pass: only where the local replica is not the primary.
IF N'$(PASS)' = N'secondaries' AND EXISTS (
    SELECT * FROM sys.availability_groups AS g
    JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.group_id = g.group_id
    WHERE g.name = @ag AND rs.is_local = 1 AND rs.role_desc = N'PRIMARY')
    RETURN;
IF EXISTS (SELECT * FROM sys.availability_groups WHERE name = @ag)
BEGIN
    INSERT @dbs SELECT database_name FROM sys.availability_databases_cluster AS d
    JOIN sys.availability_groups AS g ON g.group_id = d.group_id WHERE g.name = @ag;
    SET @q = N'DROP AVAILABILITY GROUP ' + QUOTENAME(@ag) + N';';
    EXEC (@q);
    PRINT CONCAT(N'availability group ', @ag, N' dropped on ', @@SERVERNAME);
END;
IF @@SERVERNAME <> N'hadrlab1' AND DB_ID(N'PachadataTraining') IS NOT NULL
    INSERT @dbs SELECT N'PachadataTraining' WHERE NOT EXISTS (SELECT * FROM @dbs WHERE name = N'PachadataTraining');
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM @dbs WHERE DB_ID(name) IS NOT NULL;
OPEN c;
FETCH c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF DATABASEPROPERTYEX(@db, 'Status') <> N'ONLINE'
       OR (@db = N'PachadataTraining' AND @@SERVERNAME <> N'hadrlab1')
    BEGIN
        IF DATABASEPROPERTYEX(@db, 'Status') = N'ONLINE'
        BEGIN
            SET @q = N'ALTER DATABASE ' + QUOTENAME(@db) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
            EXEC (@q);
        END;
        SET @q = N'DROP DATABASE ' + QUOTENAME(@db) + N';';
        EXEC (@q);
        PRINT CONCAT(N'copy of ', @db, N' dropped on ', @@SERVERNAME);
    END;
    FETCH c INTO @db;
END;
CLOSE c;
DEALLOCATE c;
-- The history of the seeding of PachadataTraining.
IF @@SERVERNAME = N'hadrlab1'
BEGIN
    DECLARE @sets TABLE (id int PRIMARY KEY, media int);
    INSERT @sets SELECT b.backup_set_id, b.media_set_id FROM msdb.dbo.backupset AS b
    JOIN msdb.dbo.backupmediafamily AS m ON m.media_set_id = b.media_set_id
    WHERE b.database_name = N'PachadataTraining'
      AND TRY_CAST(m.physical_device_name AS uniqueidentifier) IS NOT NULL;
    DELETE msdb.dbo.backupfile WHERE backup_set_id IN (SELECT id FROM @sets);
    DELETE msdb.dbo.backupfilegroup WHERE backup_set_id IN (SELECT id FROM @sets);
    DELETE msdb.dbo.backupset WHERE backup_set_id IN (SELECT id FROM @sets);
    DELETE msdb.dbo.backupmediafamily WHERE media_set_id IN (SELECT media FROM @sets);
    DELETE msdb.dbo.backupmediaset WHERE media_set_id IN (SELECT media FROM @sets);
END
ELSE IF EXISTS (SELECT * FROM msdb.dbo.backupset WHERE database_name = N'PachadataTraining')
     OR EXISTS (SELECT * FROM msdb.dbo.restorehistory WHERE destination_database_name = N'PachadataTraining')
BEGIN
    DECLARE @ids TABLE (id int PRIMARY KEY);
    INSERT @ids SELECT restore_history_id FROM msdb.dbo.restorehistory
    WHERE destination_database_name = N'PachadataTraining';
    DELETE msdb.dbo.restorefile WHERE restore_history_id IN (SELECT id FROM @ids);
    DELETE msdb.dbo.restorefilegroup WHERE restore_history_id IN (SELECT id FROM @ids);
    DELETE msdb.dbo.restorehistory WHERE restore_history_id IN (SELECT id FROM @ids);
    EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining';
END;
SQL
  done
done
