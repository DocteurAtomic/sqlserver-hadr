#!/usr/bin/env bash
# ci: skip (it starts hadrlab1 after 05-forced.sh, then gives the lab back with setup/install.sh)
# Clip 6.4: two primaries. Run right after 05-forced.sh: hadrlab1 stopped, hadrlab3 primary.
# hadrlab1 starts again (at most two minutes until it answers): it sees itself PRIMARY, shows
# its 1,000 rows "after hadrlab3 suspended" that the new primary does not have, and accepts an
# INSERT "written on the old primary", while hadrlab3 sees it as a SECONDARY that is
# DISCONNECTED. Nothing stops it without a cluster. Then the demotion of hadrlab1: SET (ROLE =
# SECONDARY) at once (Msg 41104 expected), OFFLINE as Learn asks, then SET (ROLE = SECONDARY)
# again every 3 seconds until it is accepted, at most a minute and a half, the time taken
# printed; RESUME once its copy shows as suspended; and the count of hadrlab1 before and after:
# its 1,001 rows of its own are gone. Then hadrlab1 becomes the primary again: hadrlab3 goes
# to synchronous commit for the time of the failover (a planned failover needs a synchronous
# primary and target), setup/ag-failover.sh AgPacha hadrlab1, hadrlab3 back to asynchronous
# commit, the secondaries closed to reads again. Appends the measures to
# evidence/module_06.md. Ends with setup/install.sh, which checks that the lab is whole again
# (AgPacha stays).
# Usage: ./demos/module_06/06-two-primaries.sh
#   With Podman: COMPOSE="podman compose" ENGINE=podman ./demos/module_06/06-two-primaries.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
export ENGINE=$engine
try() {  # a statement on an instance, its result or its error
    local n=$1; shift
    sql $n -h -1 -Q "SET NOCOUNT ON; $*" 2>&1 | grep -v '^ *$' | sed "s/^/  /" || true
}
count() {  # the rows of m06_registration per label of the two scenes, read on one instance
    sql $1 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  ', @@SERVERNAME, N': ', label, N' ', COUNT(*)) FROM m06_registration.dbo.Registration
WHERE label IN ('seen by all three', 'after hadrlab3 suspended', 'written on hadrlab3', 'written on the old primary')
GROUP BY label ORDER BY MIN(id);" 2>&1 | grep -v '^ *$' | sed 's/^\([^ ]\)/  \1/' || true
}
mine() {  # the local replica and copy on an instance
    sql $1 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  ', @@SERVERNAME, N': ', rs.role_desc, N', ', ISNULL(d.synchronization_state_desc, N'-'), N', suspended ',
              ISNULL(CAST(d.is_suspended AS varchar(1)), N'-'), IIF(d.is_suspended = 1, N' (' + d.suspend_reason_desc + N')', N''))
FROM sys.dm_hadr_availability_replica_states AS rs
LEFT JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = rs.replica_id AND d.is_local = 1
     AND d.database_id = DB_ID(N'm06_registration')
WHERE rs.is_local = 1;" 2>&1 | grep -v '^ *$' || true
}
seen_by_hadrlab3() {
    sql hadrlab3 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, rs.role_desc AS role, rs.connected_state_desc AS connected,
       ISNULL(d.synchronization_state_desc, N'-') AS sync
FROM sys.availability_replicas AS ar
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
LEFT JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id AND d.database_id = DB_ID(N'm06_registration')
ORDER BY ar.replica_server_name;"
}
sync_on_hadrlab3() {  # the sync state of the copy of hadrlab1, read on hadrlab3
    sql hadrlab3 -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL((SELECT d.synchronization_state_desc FROM sys.dm_hadr_database_replica_states AS d
        JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
        WHERE ar.replica_server_name = N'hadrlab1' AND d.database_id = DB_ID(N'm06_registration')), N'-');" | tr -d '\r' | xargs
}
if [ "$($engine inspect -f '{{.State.Running}}' hadrlab1 2>/dev/null)" = "true" ]; then
    echo "hadrlab1 is running: run 05-forced.sh first" >&2; exit 1
fi
echo "== hadrlab1: start (at most two minutes until it answers)"
$engine start hadrlab1 >/dev/null
for i in $(seq 1 120); do
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT DATABASEPROPERTYEX(N'm06_registration', 'Status');" 2>/dev/null \
        | grep -q ONLINE && break
    sleep 1
done
mine hadrlab1
count hadrlab1
try hadrlab1 "INSERT m06_registration.dbo.Registration (label, email) VALUES ('written on the old primary', 'old@pachadata.example'); SELECT N'INSERT on hadrlab1 accepted';"
count hadrlab1
echo
echo "== hadrlab3, the primary of the others"
mine hadrlab3
count hadrlab3
seen_by_hadrlab3
echo
echo "== hadrlab1: SET (ROLE = SECONDARY) at once"
try hadrlab1 "ALTER AVAILABILITY GROUP AgPacha SET (ROLE = SECONDARY);"
echo "== hadrlab1: OFFLINE, then SET (ROLE = SECONDARY) every 3 seconds"
try hadrlab1 "ALTER AVAILABILITY GROUP AgPacha OFFLINE;"
t=$(date +%s.%N)
demoted=""
for i in $(seq 1 30); do
    out=$(sql hadrlab1 -h -1 -Q "ALTER AVAILABILITY GROUP AgPacha SET (ROLE = SECONDARY);" 2>&1) && { demoted=yes; break; }
    echo "  +$(awk -v s=$t -v e=$(date +%s.%N) 'BEGIN { printf "%.0f", e - s }') s: $(echo "$out" | grep -o 'Msg [0-9]*' | head -1)"
    sleep 3
done
[ -n "$demoted" ] || { echo "hadrlab1 refuses SET (ROLE = SECONDARY) a minute and a half after OFFLINE" >&2; exit 1; }
demote_s=$(awk -v s=$t -v e=$(date +%s.%N) 'BEGIN { printf "%.0f", e - s }')
echo "  +${demote_s} s: SET (ROLE = SECONDARY) accepted"
s=""
for i in $(seq 1 60); do
    s=$(mine hadrlab1)
    case $s in *"suspended 1"*) break ;; esac
    sleep 1
done
echo "$s"
case $s in *"suspended 1"*) ;; *) echo "hadrlab1 is not suspended a minute after SET (ROLE = SECONDARY)" >&2; exit 1 ;; esac
count hadrlab1
echo "== hadrlab1: SET HADR RESUME"
resume_copy hadrlab1 m06_registration
for i in $(seq 1 60); do
    s=$(sync_on_hadrlab3)
    case $s in SYNCHRONIZING|SYNCHRONIZED) break ;; esac
    sql hadrlab3 -Q "USE m06_registration; CHECKPOINT;" >/dev/null; sleep 1
done
case $s in SYNCHRONIZING|SYNCHRONIZED) ;; *) echo "hadrlab1 has not resumed within a minute" >&2; exit 1 ;; esac
mine hadrlab1
for i in $(seq 1 30); do count hadrlab1 | grep -q 'written on hadrlab3' && break; sleep 1; done
count hadrlab1
seen_by_hadrlab3
gone=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT 1001 - COUNT(*) FROM m06_registration.dbo.Registration
    WHERE label IN ('after hadrlab3 suspended', 'written on the old primary');" | tr -d '[:space:]')
echo
echo "== hadrlab1 primary again: hadrlab3 in synchronous commit for the failover"
sql hadrlab3 -Q "ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT);"
for i in $(seq 1 60); do
    s=$(sync_on_hadrlab3)
    [ "$s" = SYNCHRONIZED ] && break
    sql hadrlab3 -Q "USE m06_registration; CHECKPOINT;" >/dev/null; sleep 1
done
[ "$s" = SYNCHRONIZED ] || { echo "hadrlab1 is not SYNCHRONIZED a minute after hadrlab3 went synchronous" >&2; exit 1; }
echo "  hadrlab1 SYNCHRONIZED"
bash setup/ag-failover.sh AgPacha hadrlab1
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT);
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab1' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = NO));
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab2' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = NO));
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = NO));
SQL
sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, rs.role_desc AS role, ar.availability_mode_desc AS mode,
       ar.secondary_role_allow_connections_desc AS secondary_allow, d.synchronization_state_desc AS sync
FROM sys.availability_replicas AS ar
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id AND d.database_id = DB_ID(N'm06_registration')
ORDER BY ar.replica_server_name;"
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 6, the old primary hadrlab1 restarted after the forced failover: it saw itself PRIMARY and accepted an INSERT while hadrlab3 was primary; SET (ROLE = SECONDARY) refused (Msg 41104) until ${demote_s} s after OFFLINE; once resumed, ${gone} of its 1,001 rows of its own (1,000 before the loss, 1 after its restart) were gone; three containers on one host" >> evidence/module_06.md
echo
echo "== setup/install.sh, the lab checked whole again"
./setup/install.sh 2>&1 | tail -1
