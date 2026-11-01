#!/usr/bin/env bash
# Clip 4.3: requiring a synchronized secondary. On hadrlab1, the group AgPacha gets
# REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1: a commit needs at least one synchronous
# secondary SYNCHRONIZED. hadrlab2 is the only synchronous one: while it is, an INSERT in
# m04_registration works. Then the copy of hadrlab2 is suspended (on hadrlab2): the INSERT
# fails at once with Msg 988, so does a SELECT, and the row is not written, which the count
# shows once hadrlab2 is resumed and SYNCHRONIZED again (at most a minute). The setting goes
# back to 0, the value that the next modules expect. Appends the result to
# evidence/module_04.md. Run after 00-setup.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
try() {  # a statement on hadrlab1, its result or its error, and its duration
    local t=$(date +%s.%N) out rc=0
    out=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; $1" 2>&1) || rc=$?
    echo "$out" | grep -v '^ *$' | sed 's/^/  /'
    echo "  (exit code $rc, $(awk -v s=$t -v e=$(date +%s.%N) 'BEGIN { printf "%.2f", e - s }') s)"
}
wait_synchronized() {
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
    THROW 50000, N'hadrlab2 is not SYNCHRONIZED a minute after RESUME', 1;
SELECT CONCAT(N'  hadrlab2 SYNCHRONIZED ', FORMAT(DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0, N'0.0'), N' s after RESUME');
SQL
}
echo "== hadrlab1: REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1"
sql hadrlab1 -Q "SET NOCOUNT ON;
ALTER AVAILABILITY GROUP AgPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1);
SELECT name, required_synchronized_secondaries_to_commit AS required FROM sys.availability_groups;
SELECT ar.replica_server_name AS replica, ar.availability_mode_desc AS mode, d.synchronization_state_desc AS sync
FROM sys.dm_hadr_database_replica_states AS d JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
WHERE d.database_id = DB_ID(N'm04_registration') AND d.is_local = 0 ORDER BY ar.replica_server_name;"
echo
echo "== hadrlab1: INSERT, hadrlab2 SYNCHRONIZED"
try "INSERT m04_registration.dbo.Registration (email) VALUES ('required-1@pachadata.example');
     SELECT CONCAT(COUNT(*), N' rows like required-%') FROM m04_registration.dbo.Registration WHERE email LIKE 'required-%';"
echo
echo "== hadrlab2: SET HADR SUSPEND"
sql hadrlab2 -Q "ALTER DATABASE m04_registration SET HADR SUSPEND;"
echo
echo "== hadrlab1: INSERT, then SELECT, hadrlab2 suspended"
try "INSERT m04_registration.dbo.Registration (email) VALUES ('required-2@pachadata.example');"
try "SELECT CONCAT(COUNT(*), N' rows like required-%') FROM m04_registration.dbo.Registration WHERE email LIKE 'required-%';"
try "SELECT CONCAT(N'PachadataTraining, same group, no secondary suspended: ', COUNT(*), N' rows in Course.Category')
     FROM PachadataTraining.Course.Category;"
echo
echo "== hadrlab2: SET HADR RESUME"
sql hadrlab2 -Q "ALTER DATABASE m04_registration SET HADR RESUME;"
wait_synchronized
echo
echo "== hadrlab1: the rows, then INSERT again"
try "SELECT email FROM m04_registration.dbo.Registration WHERE email LIKE 'required-%' ORDER BY id;"
try "INSERT m04_registration.dbo.Registration (email) VALUES ('required-3@pachadata.example');
     SELECT CONCAT(COUNT(*), N' rows like required-%') FROM m04_registration.dbo.Registration WHERE email LIKE 'required-%';"
echo
echo "== hadrlab1: REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT back to 0"
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
ALTER AVAILABILITY GROUP AgPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0);
SELECT CONCAT(name, N': required ', required_synchronized_secondaries_to_commit) FROM sys.availability_groups;"
n=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM m04_registration.dbo.Registration WHERE email = 'required-2@pachadata.example';" | tr -d '[:space:]')
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 4, REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1, the only synchronous secondary suspended: INSERT refused at once with Msg 988, ${n} row of it written; reads refused too, three containers on one host" >> evidence/module_04.md
