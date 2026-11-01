#!/usr/bin/env bash
# Exercise of module 4, starting state. Makes sure the group AgPacha exists, as module 4
# leaves it before its cleanup (setup/ag-create.sh with PachadataTraining when it is
# missing), puts hadrlab2 back in synchronous commit and the requirement of synchronized
# secondaries back to 0 if a previous attempt changed them, removes what a previous attempt
# left (ex_commit out of the group and dropped on the three instances, its backup history,
# its folder), then creates on hadrlab1 the database ex_commit, in the full recovery model:
#   dbo.Registration, where the batches write, one row per INSERT, with the name of the batch;
#   dbo.Measure, one row per batch, written by dbo.RunBatch;
#   dbo.RunBatch @batch, which runs 2,000 single-row INSERT statements in autocommit and
#   writes into dbo.Measure the commit mode of hadrlab2 at that moment, the duration, and the
#   HADR_SYNC_COMMIT waits of its own session (count and milliseconds).
# Then a full backup, ex_commit joins AgPacha, and the script waits, at most five minutes,
# until both copies are caught up. Run it again to start over.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
if [ "$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.availability_groups WHERE name = N'AgPacha'" | tr -d '[:space:]')" = 0 ]; then
    echo "AgPacha is missing: creating it with PachadataTraining (setup/ag-create.sh)."
    bash setup/ag-create.sh AgPacha PachadataTraining
fi
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
IF (SELECT required_synchronized_secondaries_to_commit FROM sys.availability_groups WHERE name = N'AgPacha') <> 0
    ALTER AVAILABILITY GROUP AgPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0);
IF (SELECT availability_mode_desc FROM sys.availability_replicas WHERE replica_server_name = N'hadrlab2') <> N'SYNCHRONOUS_COMMIT'
BEGIN
    ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab2' WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT);
    PRINT N'hadrlab2 put back in synchronous commit';
END;
IF EXISTS (SELECT * FROM sys.availability_databases_cluster WHERE database_name = N'ex_commit')
    ALTER AVAILABILITY GROUP AgPacha REMOVE DATABASE ex_commit;
SQL
for n in $nodes; do
    sql $n -h -1 <<'SQL'
SET NOCOUNT ON;
-- A secondary copy leaves the group some 20 seconds after REMOVE DATABASE on the primary:
-- wait for it, at most a minute, without touching the database.
DECLARE @t0 datetime2 = SYSDATETIME();
WHILE EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states
              WHERE is_local = 1 AND database_id = DB_ID(N'ex_commit'))
      AND DATEDIFF(second, @t0, SYSDATETIME()) < 60
    WAITFOR DELAY '00:00:01';
IF EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states
           WHERE is_local = 1 AND database_id = DB_ID(N'ex_commit'))
    THROW 50000, N'ex_commit is still joined to the group after a minute', 1;
IF DB_ID(N'ex_commit') IS NOT NULL
BEGIN
    IF DATABASEPROPERTYEX(N'ex_commit', 'Status') = N'ONLINE'
        ALTER DATABASE ex_commit SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ex_commit;
END;
DECLARE @ids TABLE (id int PRIMARY KEY);
INSERT @ids SELECT restore_history_id FROM msdb.dbo.restorehistory
WHERE destination_database_name = N'ex_commit';
DELETE msdb.dbo.restorefile WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorefilegroup WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorehistory WHERE restore_history_id IN (SELECT id FROM @ids);
IF EXISTS (SELECT * FROM msdb.dbo.backupset WHERE database_name = N'ex_commit')
    EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'ex_commit';
SQL
done
$engine exec -u 0 hadrlab1 rm -rf /var/opt/mssql/share/ex_commit
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
CREATE DATABASE ex_commit;
ALTER DATABASE ex_commit SET RECOVERY FULL;
GO
USE ex_commit;
GO
CREATE TABLE dbo.Registration (
    id int IDENTITY PRIMARY KEY,
    batch varchar(20) NOT NULL,
    email varchar(100) NOT NULL,
    written_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
CREATE TABLE dbo.Measure (
    batch varchar(20) NOT NULL PRIMARY KEY,
    hadrlab2_mode nvarchar(60) NOT NULL,
    rows_written int NOT NULL,
    duration_ms int NOT NULL,
    hadr_sync_commit_waits bigint NOT NULL,
    hadr_sync_commit_ms bigint NOT NULL,
    measured_at datetime2(0) NOT NULL DEFAULT SYSDATETIME());
GO
-- 2,000 single-row INSERT statements, each one its own transaction, then one row in
-- dbo.Measure: the commit mode of hadrlab2 when the batch starts, the duration, and the
-- HADR_SYNC_COMMIT waits of this session during the batch. Run it again with the same batch
-- name to measure again: the previous measure of that batch is replaced.
CREATE PROCEDURE dbo.RunBatch @batch varchar(20)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @mode nvarchar(60) = (SELECT availability_mode_desc FROM sys.availability_replicas
                                  WHERE replica_server_name = N'hadrlab2');
    DECLARE @c0 bigint, @w0 bigint, @t0 datetime2(3), @i int = 0;
    DELETE dbo.Registration WHERE batch = @batch;
    DELETE dbo.Measure WHERE batch = @batch;
    SELECT @c0 = ISNULL(SUM(waiting_tasks_count), 0), @w0 = ISNULL(SUM(wait_time_ms), 0)
    FROM sys.dm_exec_session_wait_stats WHERE session_id = @@SPID AND wait_type = N'HADR_SYNC_COMMIT';
    SET @t0 = SYSDATETIME();
    WHILE @i < 2000
    BEGIN
        INSERT dbo.Registration (batch, email) VALUES (@batch, CONCAT(@batch, '-', @i, '@pachadata.example'));
        SET @i += 1;
    END;
    INSERT dbo.Measure (batch, hadrlab2_mode, rows_written, duration_ms, hadr_sync_commit_waits, hadr_sync_commit_ms)
    SELECT @batch, @mode, @i, DATEDIFF(millisecond, @t0, SYSDATETIME()),
           ISNULL(SUM(waiting_tasks_count), 0) - @c0, ISNULL(SUM(wait_time_ms), 0) - @w0
    FROM sys.dm_exec_session_wait_stats WHERE session_id = @@SPID AND wait_type = N'HADR_SYNC_COMMIT';
    SELECT * FROM dbo.Measure WHERE batch = @batch;
END;
GO
USE master;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/ex_commit';
BACKUP DATABASE ex_commit TO DISK = N'/var/opt/mssql/share/ex_commit/ex_commit-full.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
ALTER AVAILABILITY GROUP AgPacha ADD DATABASE ex_commit;
GO
SQL
wait_ag_database hadrlab1 AgPacha ex_commit 300
sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, ar.availability_mode_desc AS mode,
       d.synchronization_state_desc AS sync, d.is_commit_participant AS commit_participant
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
WHERE d.database_id = DB_ID(N'ex_commit') ORDER BY ar.replica_server_name;"
