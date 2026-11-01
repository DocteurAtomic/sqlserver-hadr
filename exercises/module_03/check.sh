#!/usr/bin/env bash
# Exercise of module 3: checks that ex_inscriptions has joined AgPacha by automatic seeding,
# on the two secondaries. It reads the state, never a script. On hadrlab1: the group,
# hadrlab1 primary, ex_inscriptions one of its databases, the automatic seeding to hadrlab2
# and to hadrlab3 completed, and from sys.dm_hadr_database_replica_states, hadrlab2
# SYNCHRONIZED and hadrlab3 SYNCHRONIZING or SYNCHRONIZED. On hadrlab2 and hadrlab3: the
# local copy of ex_inscriptions joined to AgPacha, in the state its commit mode gives.
# Exits with 0 when everything holds, with 1 otherwise, saying what is missing.
# Usage: ./exercises/module_03/check.sh     (with Podman: ENGINE=podman ...)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
fail=0
out=$(sql hadrlab1 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
-- The seeding of an asynchronous replica stays in CATCHUP until the primary writes new log:
-- a checkpoint writes some, and the check reads the state two seconds later.
IF DB_ID(N'ex_inscriptions') IS NOT NULL
BEGIN
    EXEC (N'USE ex_inscriptions; CHECKPOINT;');
    WAITFOR DELAY '00:00:02';
END;
DECLARE @r TABLE (n int IDENTITY, line nvarchar(400));
DECLARE @g uniqueidentifier = (SELECT group_id FROM sys.availability_groups WHERE name = N'AgPacha');
INSERT @r SELECT IIF(@g IS NOT NULL, N'ok   hadrlab1: the group AgPacha exists',
    N'FAIL hadrlab1: the group AgPacha is missing: run exercises/module_03/1-start.sh');
INSERT @r SELECT IIF(EXISTS (SELECT * FROM sys.dm_hadr_availability_replica_states
                             WHERE group_id = @g AND is_local = 1 AND role_desc = N'PRIMARY'),
    N'ok   hadrlab1: primary of AgPacha', N'FAIL hadrlab1: is not the primary of AgPacha');
INSERT @r SELECT IIF(DB_ID(N'ex_inscriptions') IS NOT NULL, N'ok   hadrlab1: ex_inscriptions exists',
    N'FAIL hadrlab1: ex_inscriptions is missing: run exercises/module_03/1-start.sh');
INSERT @r SELECT IIF(EXISTS (SELECT * FROM sys.availability_databases_cluster
                             WHERE group_id = @g AND database_name = N'ex_inscriptions'),
    N'ok   hadrlab1: ex_inscriptions is a database of AgPacha',
    N'FAIL hadrlab1: ex_inscriptions is not in AgPacha (ALTER AVAILABILITY GROUP ... ADD DATABASE, after what it needs first)');
INSERT @r SELECT CONCAT(IIF(EXISTS (
        SELECT * FROM sys.dm_hadr_automatic_seeding AS s
        JOIN sys.availability_databases_cluster AS d ON d.group_database_id = s.ag_db_id
        WHERE d.database_name = N'ex_inscriptions' AND s.ag_remote_replica_id = ar.replica_id
          AND s.current_state = N'COMPLETED'),
        N'ok   hadrlab1: automatic seeding of ex_inscriptions to ',
        N'FAIL hadrlab1: no completed automatic seeding of ex_inscriptions (still going? run check.sh again in a few seconds) to '), ar.replica_server_name)
FROM sys.availability_replicas AS ar
WHERE ar.group_id = @g AND ar.replica_server_name IN (N'hadrlab2', N'hadrlab3');
INSERT @r SELECT CONCAT(
    IIF(drs.synchronization_state_desc = N'SYNCHRONIZED'
        OR (ar.availability_mode_desc = N'ASYNCHRONOUS_COMMIT' AND drs.synchronization_state_desc = N'SYNCHRONIZING'),
        N'ok   hadrlab1 sees ', N'FAIL hadrlab1 sees '),
    ar.replica_server_name, N' ', ISNULL(drs.synchronization_state_desc, N'without a copy'),
    N' for ex_inscriptions (', ar.availability_mode_desc, N')')
FROM sys.availability_replicas AS ar
LEFT JOIN sys.dm_hadr_database_replica_states AS drs
       ON drs.replica_id = ar.replica_id AND drs.database_id = DB_ID(N'ex_inscriptions')
WHERE ar.group_id = @g AND ar.replica_server_name IN (N'hadrlab2', N'hadrlab3');
SELECT line FROM @r ORDER BY n;
SQL
)
rc=$?
if [ $rc -ne 0 ] || [ -z "$out" ]; then echo "$out" | head -3; echo "FAIL hadrlab1 does not answer"; exit 1; fi
echo "$out"
all=$out
for n in hadrlab2 hadrlab3; do
    out=$(sql $n -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
DECLARE @state nvarchar(60), @mode nvarchar(60);
SELECT @state = drs.synchronization_state_desc, @mode = ar.availability_mode_desc
FROM sys.dm_hadr_database_replica_states AS drs
JOIN sys.availability_replicas AS ar ON ar.replica_id = drs.replica_id
JOIN sys.availability_groups AS g ON g.group_id = ar.group_id
WHERE drs.is_local = 1 AND drs.database_id = DB_ID(N'ex_inscriptions') AND g.name = N'AgPacha';
SELECT CASE
    WHEN DB_ID(N'ex_inscriptions') IS NULL
        THEN CONCAT(N'FAIL ', @@SERVERNAME, N': no copy of ex_inscriptions (the seeding has not created it)')
    WHEN @state IS NULL
        THEN CONCAT(N'FAIL ', @@SERVERNAME, N': ex_inscriptions exists but is not joined to AgPacha')
    WHEN @state = N'SYNCHRONIZED' OR (@mode = N'ASYNCHRONOUS_COMMIT' AND @state = N'SYNCHRONIZING')
        THEN CONCAT(N'ok   ', @@SERVERNAME, N': ex_inscriptions joined to AgPacha, ', @state)
    ELSE CONCAT(N'FAIL ', @@SERVERNAME, N': ex_inscriptions joined to AgPacha but ', @state, N' in ', @mode,
                N': wait for the seeding, or read the error log of this instance') END;
SQL
)
    rc=$?
    if [ $rc -ne 0 ] || [ -z "$out" ]; then echo "$out" | head -3; echo "FAIL $n does not answer"; exit 1; fi
    echo "$out"
    all="$all
$out"
done
if echo "$all" | grep -q '^FAIL'; then echo "ex_inscriptions is not protected by AgPacha yet."; exit 1; fi
echo "ex_inscriptions joined AgPacha by automatic seeding, on both secondaries."
