#!/usr/bin/env bash
# Exercise of module 4, a solution. Run after 1-start.sh. On hadrlab1: the batch measured
# with hadrlab2 in synchronous commit; then hadrlab2 goes to asynchronous commit, and the
# script waits until the change shows in the state of its copy (no longer a commit
# participant, at most a minute); the same batch measured again; hadrlab2 back in synchronous
# commit, and a wait until its copy is SYNCHRONIZED (at most a minute, a checkpoint at each
# read writes the log that moves it forward). Prints the two measures and appends them to
# evidence/module_04.md. Other solutions hold too: check.sh reads the state.
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
EXEC ex_commit.dbo.RunBatch @batch = 'synchronous';
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab2' WITH (AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT);
DECLARE @t0 datetime2(3) = SYSDATETIME();
WHILE EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states AS d
              JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
              WHERE d.database_id = DB_ID(N'ex_commit') AND ar.replica_server_name = N'hadrlab2'
                AND d.is_commit_participant = 1)
      AND DATEDIFF(second, @t0, SYSDATETIME()) < 60
    WAITFOR DELAY '00:00:00.200';
IF EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states AS d
           JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
           WHERE d.database_id = DB_ID(N'ex_commit') AND ar.replica_server_name = N'hadrlab2'
             AND d.is_commit_participant = 1)
    THROW 50000, N'hadrlab2 is still a commit participant a minute after the change', 1;
EXEC ex_commit.dbo.RunBatch @batch = 'asynchronous';
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab2' WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT);
SET @t0 = SYSDATETIME();
WHILE NOT EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states AS d
                  JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
                  WHERE d.database_id = DB_ID(N'ex_commit') AND ar.replica_server_name = N'hadrlab2'
                    AND d.synchronization_state_desc = N'SYNCHRONIZED')
      AND DATEDIFF(second, @t0, SYSDATETIME()) < 60
BEGIN
    EXEC (N'USE ex_commit; CHECKPOINT;');
    WAITFOR DELAY '00:00:00.200';
END;
IF NOT EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states AS d
               JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
               WHERE d.database_id = DB_ID(N'ex_commit') AND ar.replica_server_name = N'hadrlab2'
                 AND d.synchronization_state_desc = N'SYNCHRONIZED')
    THROW 50000, N'hadrlab2 is not SYNCHRONIZED a minute after going back to synchronous commit', 1;
SELECT batch, hadrlab2_mode, duration_ms, hadr_sync_commit_waits, hadr_sync_commit_ms
FROM ex_commit.dbo.Measure ORDER BY measured_at;
SQL
line=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
SELECT STRING_AGG(CONCAT(hadrlab2_mode, N' ', duration_ms, N' ms (', hadr_sync_commit_waits, N' HADR_SYNC_COMMIT waits, ',
                         hadr_sync_commit_ms, N' ms)'), N'; ') WITHIN GROUP (ORDER BY measured_at)
FROM ex_commit.dbo.Measure;")
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 4, exercise, 2,000 single-row INSERT statements in ex_commit on hadrlab1, hadrlab2 in each mode, three containers on one host: $line" >> evidence/module_04.md
