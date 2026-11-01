#!/usr/bin/env bash
# Exercise of module 6: checks the state that a planned failover of AgBascule to hadrlab2 leaves.
# It reads the state, never the commands: on hadrlab1, its local replica of AgBascule is
# SECONDARY; on hadrlab2, its local replica is PRIMARY; the copy of ex_bascule on hadrlab1, seen
# from hadrlab2, is SYNCHRONIZED and not suspended; the 500 rows of the batch "before failover",
# written on hadrlab1, are all in ex_bascule on hadrlab2; at least one row has been written on
# hadrlab2 (the new primary accepts writes); REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT is back
# to 0 (at 1, with two replicas, the loss of hadrlab1 would stop every read and write on
# hadrlab2: Msg 988). Exits with 0 when everything holds, with 1 otherwise, saying what is missing.
# Usage: ./exercises/module_06/check.sh     (with Podman: ENGINE=podman ...)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
role_of() {
    sql $1 -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL((SELECT rs.role_desc FROM sys.availability_groups AS g
        JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.group_id = g.group_id AND rs.is_local = 1
        WHERE g.name = N'AgBascule'), N'no AgBascule');" 2>/dev/null | tr -d '\r' | xargs
}
r1=$(role_of hadrlab1); r2=$(role_of hadrlab2)
if [ -z "$r1" ] || [ -z "$r2" ]; then echo "FAIL hadrlab1 or hadrlab2 does not answer"; exit 1; fi
fail=0
if [ "$r1" = SECONDARY ]; then echo "ok   hadrlab1: SECONDARY in AgBascule"
else echo "FAIL hadrlab1: $r1 in AgBascule, SECONDARY expected"; fail=1; fi
if [ "$r2" != PRIMARY ]; then
    echo "FAIL hadrlab2: $r2 in AgBascule, PRIMARY expected: the failover has not been done (run exercises/module_06/1-start.sh to start over)"
    echo "AgBascule has not failed over to hadrlab2 yet."; exit 1
fi
echo "ok   hadrlab2: PRIMARY in AgBascule"
out=$(sql hadrlab2 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
DECLARE @r TABLE (n int IDENTITY, line nvarchar(400));
-- A copy that has just been resumed reaches SYNCHRONIZED once the primary writes log: a
-- checkpoint writes some, and the state is read again a second later, at most ten times.
DECLARE @i int = 0;
WHILE @i < 10 AND NOT EXISTS (
    SELECT * FROM sys.dm_hadr_database_replica_states AS d
    JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
    WHERE d.database_id = DB_ID(N'ex_bascule') AND ar.replica_server_name = N'hadrlab1'
      AND d.synchronization_state_desc = N'SYNCHRONIZED' AND d.is_suspended = 0)
BEGIN
    BEGIN TRY EXEC (N'USE ex_bascule; CHECKPOINT;'); END TRY BEGIN CATCH END CATCH;
    WAITFOR DELAY '00:00:01';
    SET @i += 1;
END;
DECLARE @sync nvarchar(60), @susp bit, @reason nvarchar(60);
SELECT @sync = d.synchronization_state_desc, @susp = d.is_suspended, @reason = d.suspend_reason_desc
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
WHERE d.database_id = DB_ID(N'ex_bascule') AND ar.replica_server_name = N'hadrlab1';
INSERT @r SELECT CASE
    WHEN @sync IS NULL THEN N'FAIL hadrlab2: no state for the copy of hadrlab1: is hadrlab1 back in the group (SET (ROLE = SECONDARY))?'
    WHEN @susp = 1 THEN CONCAT(N'FAIL hadrlab2: the copy of hadrlab1 is suspended (', @reason, N'): SET HADR RESUME on hadrlab1')
    WHEN @sync <> N'SYNCHRONIZED' THEN CONCAT(N'FAIL hadrlab2: the copy of hadrlab1 is ', @sync, N', SYNCHRONIZED expected')
    ELSE N'ok   hadrlab2: the copy of ex_bascule on hadrlab1 is SYNCHRONIZED' END;
DECLARE @required int = (SELECT required_synchronized_secondaries_to_commit FROM sys.availability_groups WHERE name = N'AgBascule');
DECLARE @before int, @after int, @readable bit = 1;
BEGIN TRY
    SELECT @before = COUNT(*) FROM ex_bascule.dbo.Registration WHERE batch = 'before failover' AND written_on = N'hadrlab1';
    SELECT @after = COUNT(*) FROM ex_bascule.dbo.Registration WHERE written_on = N'hadrlab2';
END TRY
BEGIN CATCH
    SET @readable = 0;
    INSERT @r SELECT CONCAT(N'FAIL hadrlab2: ex_bascule cannot be read: Msg ', ERROR_NUMBER(), N', ', LEFT(ERROR_MESSAGE(), 150));
END CATCH;
IF @readable = 1
BEGIN
    INSERT @r SELECT IIF(@before = 500, N'ok   hadrlab2: the 500 rows of the batch "before failover" are there',
        CONCAT(N'FAIL hadrlab2: ', @before, N' rows of the batch "before failover" instead of 500: rows were lost'));
    INSERT @r SELECT IIF(@after > 0, CONCAT(N'ok   hadrlab2: ', @after, N' row(s) written on hadrlab2 after the failover'),
        N'FAIL hadrlab2: no row written on hadrlab2: write one, to show that the new primary accepts writes');
END;
INSERT @r SELECT IIF(@required = 0, N'ok   hadrlab2: REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT is 0',
    CONCAT(N'FAIL hadrlab2: REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT is ', @required, N': set it back to 0'));
SELECT line FROM @r ORDER BY n;
SQL
)
rc=$?
if [ $rc -ne 0 ] || [ -z "$out" ]; then echo "$out" | head -3; echo "FAIL hadrlab2 does not answer"; exit 1; fi
echo "$out"
if [ $fail = 1 ] || echo "$out" | grep -q '^FAIL'; then echo "The failover of AgBascule is not complete yet."; exit 1; fi
echo "AgBascule failed over to hadrlab2 without losing a row, and hadrlab1 is synchronized again."
