#!/usr/bin/env bash
# ci: skip (it shuts down hadrlab1, the primary; 06-two-primaries.sh starts it again)
# Clip 6.3: the forced failover to the asynchronous replica that is behind. The three replicas
# are opened to reads (ALLOW_CONNECTIONS = ALL) so that each one can be counted. One row
# "seen by all three", written on hadrlab1 and waited for on hadrlab3 (its last hardened LSN
# equal to the primary's, at most a minute, a checkpoint at each read). Then hadrlab3 is
# suspended (SET HADR SUSPEND on hadrlab3), which puts it behind in a way that can be
# reproduced, and 1,000 rows "after hadrlab3 suspended" are written on hadrlab1. hadrlab1 is
# lost: SHUTDOWN WITH NOWAIT, no checkpoint, as close to a crash as SQL Server allows. On
# hadrlab3, FORCE_FAILOVER_ALLOW_DATA_LOSS, and the count of rows per label on hadrlab3 and on
# hadrlab2. Then what follows, step by step: the database of the new primary is still
# suspended (SUSPEND_FROM_USER) and is resumed; hadrlab2, the synchronous replica, still
# holds the 1,000 rows and does not synchronize, even after RESUME; SET (ROLE = SECONDARY) on
# hadrlab2, then RESUME once its copy shows as suspended (at most a minute), and hadrlab2 is
# counted again. Appends the rows lost to evidence/module_06.md. Leaves hadrlab1 stopped,
# hadrlab3 primary, hadrlab2 its secondary: run 06-two-primaries.sh next, which ends with
# setup/install.sh. Run after 00-setup.sh, hadrlab1 primary.
# Usage: ./demos/module_06/05-forced.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
running() { [ "$($engine inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
try() {  # a statement on an instance, its result or its error
    local n=$1; shift
    sql $n -h -1 -Q "SET NOCOUNT ON; $*" 2>&1 | grep -v '^ *$' | sed "s/^/  /" || true
}
count() {  # the rows of m06_registration per label of this scene, read on one instance
    sql $1 -h -1 -s '|' -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  ', @@SERVERNAME, N': ', label, N' ', COUNT(*)) FROM m06_registration.dbo.Registration
WHERE label IN ('seen by all three', 'after hadrlab3 suspended') GROUP BY label ORDER BY MIN(id);" 2>&1 \
        | grep -v '^ *$' | sed 's/^\([^ ]\)/  \1/' || true
}
mine() {  # the local replica and copy on an instance: role, sync state, suspended, reason
    sql $1 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  ', @@SERVERNAME, N': ', rs.role_desc, N', ', d.synchronization_state_desc, N', suspended ',
              d.is_suspended, IIF(d.is_suspended = 1, N' (' + d.suspend_reason_desc + N')', N''))
FROM sys.dm_hadr_availability_replica_states AS rs
JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = rs.replica_id AND d.is_local = 1
WHERE rs.is_local = 1 AND d.database_id = DB_ID(N'm06_registration');" 2>&1 | grep -v '^ *$' || true
}
[ "$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT rs.role_desc FROM sys.dm_hadr_availability_replica_states AS rs
    JOIN sys.availability_groups AS g ON g.group_id = rs.group_id WHERE g.name = N'AgPacha' AND rs.is_local = 1;" \
    | tr -d '[:space:]')" = PRIMARY ] || { echo "hadrlab1 is not the primary of AgPacha: run 00-setup.sh" >&2; exit 1; }
echo "== hadrlab1: the three replicas readable (ALLOW_CONNECTIONS = ALL), a row seen by all three"
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
ALTER AVAILABILITY GROUP AgPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0);
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab1' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = ALL));
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab2' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = ALL));
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = ALL));
INSERT m06_registration.dbo.Registration (label, email) VALUES ('seen by all three', 'all@pachadata.example');
SQL
# The secondaries read the new ALLOW_CONNECTIONS a few seconds later, and hadrlab3, asynchronous,
# redoes the row a moment after the commit: read until each one shows it, at most a minute, with
# a checkpoint on hadrlab1 at each read (an asynchronous copy moves forward when log is written).
for n in hadrlab2 hadrlab3; do
    for i in $(seq 1 60); do
        count $n | grep -q 'seen by all three' && break
        sql hadrlab1 -Q "USE m06_registration; CHECKPOINT;" >/dev/null; sleep 1
    done
    count $n | grep -q 'seen by all three' || { echo "$n does not show the row within a minute" >&2; exit 1; }
done
for n in hadrlab1 hadrlab2 hadrlab3; do count $n; done
echo
echo "== hadrlab3: SET HADR SUSPEND, then 1,000 rows on hadrlab1"
sql hadrlab3 -Q "ALTER DATABASE m06_registration SET HADR SUSPEND;"
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; DECLARE @i int = 0;
WHILE @i < 1000 BEGIN
    INSERT m06_registration.dbo.Registration (label, email) VALUES ('after hadrlab3 suspended', CONCAT('late', @i, '@pachadata.example'));
    SET @i += 1;
END;"
# hadrlab2 hardens each commit before it is acknowledged, but redoes it a moment later: read
# until it shows the 1,000 rows, at most a minute.
for i in $(seq 1 60); do count hadrlab2 | grep -q 'suspended 1000' && break; sleep 1; done
count hadrlab2 | grep -q 'suspended 1000' || { echo "hadrlab2 does not show the 1,000 rows within a minute" >&2; exit 1; }
for n in hadrlab1 hadrlab2 hadrlab3; do count $n; done
sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, ar.availability_mode_desc AS mode, d.synchronization_state_desc AS sync,
       d.is_suspended AS suspended, IIF(d.last_hardened_lsn = p.last_hardened_lsn, N'equal', N'behind') AS lsn_vs_primary
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
JOIN sys.dm_hadr_database_replica_states AS p ON p.group_database_id = d.group_database_id AND p.is_local = 1
WHERE d.database_id = DB_ID(N'm06_registration') ORDER BY ar.replica_server_name;"
echo
echo "== hadrlab1: SHUTDOWN WITH NOWAIT (the primary is lost)"
sql hadrlab1 -Q "SHUTDOWN WITH NOWAIT;" >/dev/null 2>&1 || true
for i in $(seq 1 60); do running hadrlab1 || break; sleep 1; done
if running hadrlab1; then echo "hadrlab1 still runs 60 s after SHUTDOWN" >&2; exit 1; fi
echo "  hadrlab1 stopped"
echo
echo "== hadrlab3: FORCE_FAILOVER_ALLOW_DATA_LOSS"
t=$(date +%s.%N)
try hadrlab3 "ALTER AVAILABILITY GROUP AgPacha FORCE_FAILOVER_ALLOW_DATA_LOSS;"
echo "  ($(awk -v s=$t -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }') s)"
mine hadrlab3
count hadrlab3
try hadrlab3 "INSERT m06_registration.dbo.Registration (label, email) VALUES ('written on hadrlab3', 'new@pachadata.example'); SELECT N'INSERT on hadrlab3 accepted';"
echo
echo "== hadrlab3: SET HADR RESUME on the new primary"
sql hadrlab3 -Q "ALTER DATABASE m06_registration SET HADR RESUME;"
mine hadrlab3
echo
echo "== hadrlab2, the synchronous replica, still running"
mine hadrlab2
count hadrlab2
echo "== hadrlab2: SET HADR RESUME, then 10 seconds"
try hadrlab2 "ALTER DATABASE m06_registration SET HADR RESUME;"
sleep 10
mine hadrlab2
echo "== hadrlab2: SET (ROLE = SECONDARY), then RESUME once its copy is suspended (at most a minute)"
try hadrlab2 "ALTER AVAILABILITY GROUP AgPacha SET (ROLE = SECONDARY);"
s=""
for i in $(seq 1 60); do
    s=$(mine hadrlab2)
    case $s in *"suspended 1"*) break ;; esac
    sleep 1
done
echo "$s"
count hadrlab2
case $s in *"suspended 1"*) ;; *) echo "hadrlab2 is not suspended a minute after SET (ROLE = SECONDARY)" >&2; exit 1 ;; esac
sql hadrlab2 -Q "ALTER DATABASE m06_registration SET HADR RESUME;"
# Read on the new primary until hadrlab2 is connected and synchronizing, at most a minute.
for i in $(seq 1 60); do
    s=$(sql hadrlab3 -h -1 -Q "SET NOCOUNT ON; SELECT d.synchronization_state_desc FROM sys.dm_hadr_database_replica_states AS d
        JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
        WHERE ar.replica_server_name = N'hadrlab2' AND d.database_id = DB_ID(N'm06_registration');" | tr -d '\r' | xargs)
    case $s in SYNCHRONIZING|SYNCHRONIZED) break ;; esac
    sql hadrlab3 -Q "USE m06_registration; CHECKPOINT;" >/dev/null; sleep 1
done
case $s in SYNCHRONIZING|SYNCHRONIZED) ;; *) echo "hadrlab2 has not resumed within a minute" >&2; exit 1 ;; esac
mine hadrlab2
for i in $(seq 1 30); do count hadrlab2 | grep -q 'seen by all three' && break; sleep 1; done
count hadrlab2
echo
echo "== hadrlab3: the replicas seen by the new primary"
sql hadrlab3 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, rs.role_desc AS role, rs.connected_state_desc AS connected,
       ISNULL(d.synchronization_state_desc, N'-') AS sync
FROM sys.availability_replicas AS ar
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
LEFT JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id AND d.database_id = DB_ID(N'm06_registration')
ORDER BY ar.replica_server_name;"
lost=$(sql hadrlab3 -h -1 -Q "SET NOCOUNT ON; SELECT 1000 - COUNT(*) FROM m06_registration.dbo.Registration WHERE label = 'after hadrlab3 suspended';" | tr -d '[:space:]')
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 6, forced failover to hadrlab3 (asynchronous, suspended before 1,000 commits) after the loss of hadrlab1: ${lost} rows committed on hadrlab1 and acknowledged to the client are missing on the new primary, and hadrlab2 (synchronous, still running) lost them too once resumed; three containers on one host" >> evidence/module_06.md
echo "Rows lost: $lost of 1000. hadrlab1 is stopped: run demos/module_06/06-two-primaries.sh."
