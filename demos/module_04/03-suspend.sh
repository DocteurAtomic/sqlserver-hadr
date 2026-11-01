#!/usr/bin/env bash
# Clip 4.2: suspend and resume the data movement of one database, a gesture that modules 6
# and 10 use again. On hadrlab2, the synchronous secondary: ALTER DATABASE m04_registration
# SET HADR SUSPEND. On hadrlab1: the copy of hadrlab2 NOT SYNCHRONIZING, with its reason, no
# longer a commit participant, and 500 single-row INSERT statements that no longer wait for it
# (no HADR_SYNC_COMMIT); the LSN of hadrlab2 stays behind. Then SET HADR RESUME on hadrlab2,
# and the time until hadrlab2 is SYNCHRONIZED again, read on the primary (at most a minute,
# with a checkpoint at each read, which writes log and moves the copy forward).
# Run after 00-setup.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
copy() {  # the copy of m04_registration on hadrlab2, seen from hadrlab1
    sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, d.synchronization_state_desc AS sync,
       d.is_suspended AS suspended, d.suspend_reason_desc AS reason,
       d.is_commit_participant AS commit_participant,
       IIF(d.last_hardened_lsn = p.last_hardened_lsn, N'equal', N'behind') AS lsn_vs_primary
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
CROSS JOIN (SELECT last_hardened_lsn FROM sys.dm_hadr_database_replica_states
            WHERE is_local = 1 AND database_id = DB_ID(N'm04_registration')) AS p
WHERE d.database_id = DB_ID(N'm04_registration') AND ar.replica_server_name = N'hadrlab2';"
}
inserts() {  # 500 single-row transactions on hadrlab1, with the HADR_SYNC_COMMIT waits of the session
    sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @c0 bigint = ISNULL((SELECT waiting_tasks_count FROM sys.dm_exec_session_wait_stats
                             WHERE session_id = @@SPID AND wait_type = N'HADR_SYNC_COMMIT'), 0),
        @t0 datetime2(3) = SYSDATETIME(), @i int = 0;
WHILE @i < 500
BEGIN
    INSERT m04_registration.dbo.Registration (email) VALUES (CONCAT('suspend', @i, '@pachadata.example'));
    SET @i += 1;
END;
SELECT CONCAT(N'500 INSERT in ', DATEDIFF(millisecond, @t0, SYSDATETIME()), N' ms, ',
       ISNULL((SELECT waiting_tasks_count FROM sys.dm_exec_session_wait_stats
               WHERE session_id = @@SPID AND wait_type = N'HADR_SYNC_COMMIT'), 0) - @c0, N' HADR_SYNC_COMMIT waits');
SQL
}
echo "== hadrlab1, before"
copy
inserts
echo
echo "== hadrlab2: SET HADR SUSPEND"
sql hadrlab2 -Q "ALTER DATABASE m04_registration SET HADR SUSPEND;"
echo
echo "== hadrlab1, hadrlab2 suspended"
copy
inserts
copy
echo
echo "== hadrlab2: SET HADR RESUME"
sql hadrlab2 -Q "ALTER DATABASE m04_registration SET HADR RESUME;"
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @t0 datetime2(3) = SYSDATETIME();
WHILE NOT EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states AS d
                  JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
                  WHERE d.database_id = DB_ID(N'm04_registration') AND ar.replica_server_name = N'hadrlab2'
                    AND d.synchronization_state_desc = N'SYNCHRONIZED')
      AND DATEDIFF(second, @t0, SYSDATETIME()) < 60
BEGIN
    EXEC (N'USE m04_registration; CHECKPOINT;');
    WAITFOR DELAY '00:00:00.200';
END;
IF NOT EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states AS d
               JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
               WHERE d.database_id = DB_ID(N'm04_registration') AND ar.replica_server_name = N'hadrlab2'
                 AND d.synchronization_state_desc = N'SYNCHRONIZED')
    THROW 50000, N'hadrlab2 is not SYNCHRONIZED a minute after RESUME', 1;
SELECT CONCAT(N'hadrlab2 SYNCHRONIZED ', FORMAT(DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0, N'0.0'),
              N' s after RESUME');
SQL
echo
echo "== hadrlab1, after"
copy
inserts
