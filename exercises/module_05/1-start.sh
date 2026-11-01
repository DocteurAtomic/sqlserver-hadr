#!/usr/bin/env bash
# Exercise of module 5, starting state. Makes sure the group AgPacha exists, as module 5
# leaves it before its cleanup (setup/ag-create.sh with PachadataTraining when it is
# missing), and puts back the settings that the exercise asks to change, if a previous
# attempt changed them: AUTOMATED_BACKUP_PREFERENCE = SECONDARY, BACKUP_PRIORITY 50 on the
# three replicas, hadrlab3 in asynchronous commit and ALLOW_CONNECTIONS = NO. Removes what a
# previous attempt left (ex_backup out of the group, ex_backup and ex_backup_verif dropped on
# the three instances, their backup and restore history, their folder), then creates on
# hadrlab1 the database ex_backup, in the full recovery model, with dbo.Invoice (1,000 rows)
# and dbo.AddInvoice, which writes one more invoice; then a full backup, ex_backup joins
# AgPacha, and the script waits, at most five minutes, until both copies are caught up.
# Run it again to start over.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
if [ "$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.availability_groups WHERE name = N'AgPacha'" | tr -d '[:space:]')" = 0 ]; then
    echo "AgPacha is missing: creating it with PachadataTraining (setup/ag-create.sh)."
    bash setup/ag-create.sh AgPacha PachadataTraining
fi
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
IF (SELECT automated_backup_preference_desc FROM sys.availability_groups WHERE name = N'AgPacha') <> N'secondary'
    ALTER AVAILABILITY GROUP AgPacha SET (AUTOMATED_BACKUP_PREFERENCE = SECONDARY);
DECLARE @r sysname, @q nvarchar(max);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT replica_server_name FROM sys.availability_replicas WHERE backup_priority <> 50;
OPEN c;
FETCH c INTO @r;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @q = N'ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N''' + @r + N''' WITH (BACKUP_PRIORITY = 50);';
    EXEC (@q);
    FETCH c INTO @r;
END;
CLOSE c;
DEALLOCATE c;
IF (SELECT availability_mode_desc FROM sys.availability_replicas WHERE replica_server_name = N'hadrlab3') <> N'ASYNCHRONOUS_COMMIT'
    ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT);
IF (SELECT secondary_role_allow_connections_desc FROM sys.availability_replicas WHERE replica_server_name = N'hadrlab3') <> N'NO'
    ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = NO));
IF EXISTS (SELECT * FROM sys.availability_databases_cluster WHERE database_name = N'ex_backup')
    ALTER AVAILABILITY GROUP AgPacha REMOVE DATABASE ex_backup;
SQL
for n in $nodes; do
    sql $n -h -1 <<'SQL'
SET NOCOUNT ON;
-- A secondary copy leaves the group some 20 seconds after REMOVE DATABASE on the primary:
-- wait for it, at most a minute, without touching the database.
DECLARE @t0 datetime2 = SYSDATETIME();
WHILE EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states
              WHERE is_local = 1 AND database_id = DB_ID(N'ex_backup'))
      AND DATEDIFF(second, @t0, SYSDATETIME()) < 60
    WAITFOR DELAY '00:00:01';
IF EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states
           WHERE is_local = 1 AND database_id = DB_ID(N'ex_backup'))
    THROW 50000, N'ex_backup is still joined to the group after a minute', 1;
DECLARE @db sysname, @q nvarchar(max);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM sys.databases WHERE name IN (N'ex_backup', N'ex_backup_verif');
OPEN c;
FETCH c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF DATABASEPROPERTYEX(@db, 'Status') = N'ONLINE'
    BEGIN
        SET @q = N'ALTER DATABASE ' + QUOTENAME(@db) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
        EXEC (@q);
    END;
    SET @q = N'DROP DATABASE ' + QUOTENAME(@db) + N';';
    EXEC (@q);
    FETCH c INTO @db;
END;
CLOSE c;
DEALLOCATE c;
DECLARE @ids TABLE (id int PRIMARY KEY);
INSERT @ids SELECT restore_history_id FROM msdb.dbo.restorehistory
WHERE destination_database_name IN (N'ex_backup', N'ex_backup_verif');
DELETE msdb.dbo.restorefile WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorefilegroup WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorehistory WHERE restore_history_id IN (SELECT id FROM @ids);
IF EXISTS (SELECT * FROM msdb.dbo.backupset WHERE database_name = N'ex_backup')
    EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'ex_backup';
SQL
done
$engine exec -u 0 hadrlab1 rm -rf /var/opt/mssql/share/ex_backup
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
CREATE DATABASE ex_backup;
ALTER DATABASE ex_backup SET RECOVERY FULL;
GO
USE ex_backup;
GO
CREATE TABLE dbo.Invoice (
    id int IDENTITY PRIMARY KEY,
    amount decimal(10, 2) NOT NULL,
    issued_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
INSERT dbo.Invoice (amount)
SELECT TOP (1000) 100 + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 900 FROM sys.all_objects;
GO
-- One more invoice, written on the primary: run it between your backups, to see in the restored
-- database which backup brought which row.
CREATE PROCEDURE dbo.AddInvoice
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.Invoice (amount) VALUES (42);
    SELECT TOP (1) id, amount, issued_at FROM dbo.Invoice ORDER BY id DESC;
END;
GO
USE master;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/ex_backup';
BACKUP DATABASE ex_backup TO DISK = N'/var/opt/mssql/share/ex_backup/ex_backup-start.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
ALTER AVAILABILITY GROUP AgPacha ADD DATABASE ex_backup;
GO
SQL
wait_ag_database hadrlab1 AgPacha ex_backup 300
sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, ar.availability_mode_desc AS mode, ar.backup_priority,
       ar.secondary_role_allow_connections_desc AS secondary_allow, d.synchronization_state_desc AS sync
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
WHERE d.database_id = DB_ID(N'ex_backup') ORDER BY ar.replica_server_name;"
