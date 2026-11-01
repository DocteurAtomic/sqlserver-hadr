#!/usr/bin/env bash
# Exercise of module 8: checks the state of AgRepair once repaired. It reads the state, never
# the commands nor the report: on hadrlab1, the primary, the copies of ex_repair on hadrlab2
# and hadrlab3 are not suspended, hadrlab2 (synchronous) is SYNCHRONIZED and hadrlab3
# (asynchronous) SYNCHRONIZING or SYNCHRONIZED, with no log left to send (the redo queue is not
# read: the checkpoints that make a resumed copy catch up write log of their own); on each
# secondary, the database is ONLINE and its file ex_repair_archive exists and is ONLINE.
# Exits with 0 when everything holds, with 1 otherwise, saying what is missing.
# Usage: ./exercises/module_08/check.sh     (with Podman: ENGINE=podman ...)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
fail=0
out=$(sql hadrlab1 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
IF NOT EXISTS (SELECT * FROM sys.availability_groups AS g
               JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.group_id = g.group_id AND rs.is_local = 1
               WHERE g.name = N'AgRepair' AND rs.role_desc = N'PRIMARY')
BEGIN
    PRINT N'FAIL hadrlab1: not the primary of AgRepair (run exercises/module_08/1-start.sh)';
    RETURN;
END;
-- A copy just resumed catches up once the primary writes log: a checkpoint writes some, and
-- the state is read again a second later, at most twenty times.
DECLARE @i int = 0;
WHILE @i < 20 AND EXISTS (
    SELECT * FROM sys.availability_replicas AS ar
    JOIN sys.availability_groups AS g ON g.group_id = ar.group_id AND g.name = N'AgRepair'
    LEFT JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id AND d.database_id = DB_ID(N'ex_repair')
    WHERE ar.replica_server_name <> @@SERVERNAME
      AND (d.is_suspended IS NULL OR d.is_suspended = 1 OR d.log_send_queue_size > 0
           OR d.synchronization_state_desc NOT IN (N'SYNCHRONIZED', N'SYNCHRONIZING')
           OR (ar.availability_mode_desc = N'SYNCHRONOUS_COMMIT' AND d.synchronization_state_desc <> N'SYNCHRONIZED')))
BEGIN
    BEGIN TRY EXEC (N'USE ex_repair; CHECKPOINT;'); END TRY BEGIN CATCH END CATCH;
    WAITFOR DELAY '00:00:01';
    SET @i += 1;
END;
SELECT CASE
    WHEN d.replica_id IS NULL THEN CONCAT(N'FAIL ', ar.replica_server_name, N': no copy of ex_repair in AgRepair')
    WHEN d.is_suspended = 1 THEN CONCAT(N'FAIL ', ar.replica_server_name, N': the copy of ex_repair is suspended (',
         d.suspend_reason_desc, N'): find the cause before resuming it')
    WHEN ar.availability_mode_desc = N'SYNCHRONOUS_COMMIT' AND d.synchronization_state_desc <> N'SYNCHRONIZED'
         THEN CONCAT(N'FAIL ', ar.replica_server_name, N': the copy of ex_repair is ', d.synchronization_state_desc, N', SYNCHRONIZED expected')
    WHEN d.synchronization_state_desc NOT IN (N'SYNCHRONIZED', N'SYNCHRONIZING')
         THEN CONCAT(N'FAIL ', ar.replica_server_name, N': the copy of ex_repair is ', d.synchronization_state_desc)
    WHEN d.log_send_queue_size > 0
         THEN CONCAT(N'FAIL ', ar.replica_server_name, N': the copy is not caught up (', d.log_send_queue_size,
              N' KB of log not sent yet)')
    ELSE CONCAT(N'ok   hadrlab1: the copy of ex_repair on ', ar.replica_server_name, N' is ', d.synchronization_state_desc,
         N', not suspended, caught up') END
FROM sys.availability_replicas AS ar
JOIN sys.availability_groups AS g ON g.group_id = ar.group_id AND g.name = N'AgRepair'
LEFT JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id AND d.database_id = DB_ID(N'ex_repair')
WHERE ar.replica_server_name <> @@SERVERNAME
ORDER BY ar.replica_server_name;
SQL
)
if [ -z "$out" ]; then echo "FAIL hadrlab1 does not answer"; exit 1; fi
echo "$out"
echo "$out" | grep -q '^FAIL' && fail=1
for n in hadrlab2 hadrlab3; do
    line=$(sql $n -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(ISNULL(CONVERT(nvarchar(60), DATABASEPROPERTYEX(N'ex_repair', 'Status')), N'missing'), N' ',
        ISNULL((SELECT state_desc FROM sys.master_files WHERE database_id = DB_ID(N'ex_repair') AND name = N'ex_repair_archive'), N'no-file'));" 2>&1 | tr -d '\r' | xargs)
    case $line in
        "ONLINE ONLINE") echo "ok   $n: ex_repair ONLINE, its file ex_repair_archive ONLINE" ;;
        *) echo "FAIL $n: ex_repair and its file ex_repair_archive are '$line', 'ONLINE ONLINE' expected"; fail=1 ;;
    esac
done
if [ $fail -ne 0 ]; then echo "AgRepair is not repaired yet."; exit 1; fi
echo "AgRepair is repaired: both secondaries are caught up."
