#!/usr/bin/env bash
# Exercise of module 4: checks the two measures and the state they leave. It reads the state,
# never a script, and never compares a duration with a threshold: on a given run, the
# synchronous batch need not be the slower one. On hadrlab1, in ex_commit:
#   a measure taken with hadrlab2 in SYNCHRONOUS_COMMIT, its 2,000 rows in dbo.Registration,
#   and HADR_SYNC_COMMIT waits counted during it (more than zero);
#   a measure taken with hadrlab2 in ASYNCHRONOUS_COMMIT, its 2,000 rows;
#   the gap of HADR_SYNC_COMMIT between them: fewer waits in the asynchronous measure;
#   hadrlab2 back in SYNCHRONOUS_COMMIT, its copy of ex_commit SYNCHRONIZED.
# Exits with 0 when everything holds, with 1 otherwise, saying what is missing.
# Usage: ./exercises/module_04/check.sh     (with Podman: ENGINE=podman ...)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
out=$(sql hadrlab1 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
DECLARE @r TABLE (n int IDENTITY, line nvarchar(400));
IF DB_ID(N'ex_commit') IS NULL
BEGIN
    SELECT N'FAIL hadrlab1: ex_commit is missing: run exercises/module_04/1-start.sh';
    RETURN;
END;
-- A synchronous copy that has just come back reaches SYNCHRONIZED once the primary writes
-- log: a checkpoint writes some, and the check reads the state a second later, at most
-- ten times.
DECLARE @i int = 0;
WHILE @i < 10 AND NOT EXISTS (
    SELECT * FROM sys.dm_hadr_database_replica_states AS d
    JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
    WHERE d.database_id = DB_ID(N'ex_commit') AND ar.replica_server_name = N'hadrlab2'
      AND ar.availability_mode_desc = N'SYNCHRONOUS_COMMIT' AND d.synchronization_state_desc = N'SYNCHRONIZED')
BEGIN
    IF NOT EXISTS (SELECT * FROM sys.availability_replicas
                   WHERE replica_server_name = N'hadrlab2' AND availability_mode_desc = N'SYNCHRONOUS_COMMIT')
        BREAK;
    EXEC (N'USE ex_commit; CHECKPOINT;');
    WAITFOR DELAY '00:00:01';
    SET @i += 1;
END;
DECLARE @sw bigint, @aw bigint, @sr int, @ar int;
SELECT TOP (1) @sw = m.hadr_sync_commit_waits,
       @sr = (SELECT COUNT(*) FROM ex_commit.dbo.Registration AS r WHERE r.batch = m.batch)
FROM ex_commit.dbo.Measure AS m WHERE m.hadrlab2_mode = N'SYNCHRONOUS_COMMIT' ORDER BY m.measured_at DESC;
SELECT TOP (1) @aw = m.hadr_sync_commit_waits,
       @ar = (SELECT COUNT(*) FROM ex_commit.dbo.Registration AS r WHERE r.batch = m.batch)
FROM ex_commit.dbo.Measure AS m WHERE m.hadrlab2_mode = N'ASYNCHRONOUS_COMMIT' ORDER BY m.measured_at DESC;
INSERT @r SELECT IIF(EXISTS (SELECT * FROM sys.availability_databases_cluster AS d
                             JOIN sys.availability_groups AS g ON g.group_id = d.group_id
                             WHERE g.name = N'AgPacha' AND d.database_name = N'ex_commit'),
    N'ok   hadrlab1: ex_commit is a database of AgPacha',
    N'FAIL hadrlab1: ex_commit is not in AgPacha: run exercises/module_04/1-start.sh');
INSERT @r SELECT CASE
    WHEN @sr IS NULL THEN N'FAIL hadrlab1: no measure taken with hadrlab2 in SYNCHRONOUS_COMMIT (EXEC ex_commit.dbo.RunBatch)'
    WHEN @sr <> 2000 THEN CONCAT(N'FAIL hadrlab1: the synchronous measure has ', @sr, N' rows in dbo.Registration instead of 2000: run it again')
    WHEN @sw = 0 THEN N'FAIL hadrlab1: the synchronous measure counted no HADR_SYNC_COMMIT wait: was the copy of hadrlab2 suspended or disconnected? Measure again once it is SYNCHRONIZED'
    ELSE CONCAT(N'ok   hadrlab1: synchronous measure, 2000 rows, ', @sw, N' HADR_SYNC_COMMIT waits') END;
INSERT @r SELECT CASE
    WHEN @ar IS NULL THEN N'FAIL hadrlab1: no measure taken with hadrlab2 in ASYNCHRONOUS_COMMIT (MODIFY REPLICA, then RunBatch)'
    WHEN @ar <> 2000 THEN CONCAT(N'FAIL hadrlab1: the asynchronous measure has ', @ar, N' rows in dbo.Registration instead of 2000: run it again')
    ELSE CONCAT(N'ok   hadrlab1: asynchronous measure, 2000 rows, ', @aw, N' HADR_SYNC_COMMIT waits') END;
INSERT @r SELECT CASE
    WHEN @sw IS NULL OR @aw IS NULL THEN N'FAIL hadrlab1: the gap of HADR_SYNC_COMMIT needs both measures'
    WHEN @aw >= @sw THEN CONCAT(N'FAIL hadrlab1: the asynchronous measure has as many HADR_SYNC_COMMIT waits as the synchronous one (',
                                @aw, N' and ', @sw, N'): was another secondary synchronous at that moment?')
    ELSE CONCAT(N'ok   hadrlab1: HADR_SYNC_COMMIT, ', @sw, N' waits in synchronous commit against ', @aw, N' in asynchronous commit') END;
INSERT @r SELECT CASE
    WHEN NOT EXISTS (SELECT * FROM sys.availability_replicas
                     WHERE replica_server_name = N'hadrlab2' AND availability_mode_desc = N'SYNCHRONOUS_COMMIT')
        THEN N'FAIL hadrlab1: hadrlab2 is not back in SYNCHRONOUS_COMMIT'
    WHEN NOT EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states AS d
                     JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
                     WHERE d.database_id = DB_ID(N'ex_commit') AND ar.replica_server_name = N'hadrlab2'
                       AND d.synchronization_state_desc = N'SYNCHRONIZED')
        THEN N'FAIL hadrlab1: hadrlab2 is in SYNCHRONOUS_COMMIT but its copy of ex_commit is not SYNCHRONIZED: is it suspended? (SET HADR RESUME)'
    ELSE N'ok   hadrlab1: hadrlab2 back in SYNCHRONOUS_COMMIT, ex_commit SYNCHRONIZED' END;
SELECT line FROM @r ORDER BY n;
SQL
)
rc=$?
if [ $rc -ne 0 ] || [ -z "$out" ]; then echo "$out" | head -3; echo "FAIL hadrlab1 does not answer"; exit 1; fi
echo "$out"
if echo "$out" | grep -q '^FAIL'; then echo "The two measures of ex_commit are not complete yet."; exit 1; fi
echo "Both measures of ex_commit are recorded, and hadrlab2 is synchronous again."
