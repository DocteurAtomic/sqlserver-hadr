#!/usr/bin/env bash
# ci: skip (it freezes the container of hadrlab2 with "pause", a failure provoked by hand)
# Clip 4.3: the secondary that no longer answers, under the same requirement. With
# REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1 on AgPacha, the container of hadrlab2 is
# frozen ("pause": SQL Server stops answering without stopping, as a hung server or a
# network cut would). On hadrlab1, an INSERT numbered "frozen-1" waits for the session
# timeout of the replica (SESSION_TIMEOUT, 10 seconds by default), then fails with message
# 3303 ("Remote harden ... failed") and its session is killed (596); the next statements
# fail with Msg 988. hadrlab2 is unfrozen ("unpause"), becomes SYNCHRONIZED again (at most a
# minute), and the count shows that the row of the failed INSERT was written all the same.
# The setting goes back to 0. Appends the result to evidence/module_04.md. Run after
# 00-setup.sh; leaves the lab as it found it, hadrlab2 running and SYNCHRONIZED.
# Usage: ./demos/module_04/05-frozen.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
try() {  # a statement on hadrlab1, its result or its error, and its duration
    local t=$(date +%s.%N) out rc=0
    out=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; $1" 2>&1) || rc=$?
    echo "$out" | grep -v '^ *$' | sed 's/^/  /'
    echo "  (exit code $rc, $(awk -v s=$t -v e=$(date +%s.%N) 'BEGIN { printf "%.2f", e - s }') s)"
}
# Whatever happens, hadrlab2 is unfrozen at the end.
trap '$engine unpause hadrlab2 >/dev/null 2>&1 || true' EXIT
echo "== hadrlab1: REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1, and the session timeouts"
sql hadrlab1 -Q "SET NOCOUNT ON;
ALTER AVAILABILITY GROUP AgPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1);
SELECT ar.replica_server_name AS replica, ar.availability_mode_desc AS mode, ar.session_timeout AS session_timeout_s
FROM sys.availability_replicas AS ar ORDER BY ar.replica_server_name;"
echo
echo "== hadrlab2: pause (the container freezes)"
$engine pause hadrlab2 >/dev/null
echo "  hadrlab2 $($engine inspect -f '{{.State.Status}}' hadrlab2)"
echo
echo "== hadrlab1: INSERT frozen-1, then INSERT frozen-2, then SELECT"
t1=$(date +%s.%N)
try "INSERT m04_registration.dbo.Registration (email) VALUES ('frozen-1@pachadata.example');"
waited=$(awk -v s=$t1 -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }')
try "INSERT m04_registration.dbo.Registration (email) VALUES ('frozen-2@pachadata.example');"
try "SELECT COUNT(*) FROM m04_registration.dbo.Registration;"
sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, rs.connected_state_desc AS connected,
       d.synchronization_state_desc AS sync, d.is_commit_participant AS commit_participant
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
WHERE d.database_id = DB_ID(N'm04_registration') AND d.is_local = 0 ORDER BY ar.replica_server_name;"
echo
echo "== hadrlab2: unpause"
$engine unpause hadrlab2 >/dev/null
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @t0 datetime2(3) = SYSDATETIME();
WHILE NOT EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states AS d
                  JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
                  WHERE d.database_id = DB_ID(N'm04_registration') AND ar.replica_server_name = N'hadrlab2'
                    AND d.synchronization_state_desc = N'SYNCHRONIZED')
      AND DATEDIFF(second, @t0, SYSDATETIME()) < 60
    WAITFOR DELAY '00:00:00.200';
IF NOT EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states AS d
               JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
               WHERE d.database_id = DB_ID(N'm04_registration') AND ar.replica_server_name = N'hadrlab2'
                 AND d.synchronization_state_desc = N'SYNCHRONIZED')
    THROW 50000, N'hadrlab2 is not SYNCHRONIZED a minute after unpause', 1;
SELECT CONCAT(N'  hadrlab2 SYNCHRONIZED ', FORMAT(DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0, N'0.0'), N' s after unpause');
SQL
echo
echo "== hadrlab1: the rows like frozen-%, and the error log"
try "SELECT email FROM m04_registration.dbo.Registration WHERE email LIKE 'frozen-%' ORDER BY id;"
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; EXEC sys.xp_readerrorlog 0, 1, N'Remote harden';" | tail -1 | cut -c1-200
echo
echo "== hadrlab1: REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT back to 0"
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
ALTER AVAILABILITY GROUP AgPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0);
SELECT CONCAT(name, N': required ', required_synchronized_secondaries_to_commit) FROM sys.availability_groups;"
n1=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM m04_registration.dbo.Registration WHERE email = 'frozen-1@pachadata.example';" | tr -d '[:space:]')
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 4, REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1, the only synchronous secondary frozen (container paused): the INSERT waited ${waited} s (session timeout 10 s), failed with 3303 then 596, and ${n1} row of it was written on the primary; Msg 988 until the secondary came back, three containers on one host" >> evidence/module_04.md
