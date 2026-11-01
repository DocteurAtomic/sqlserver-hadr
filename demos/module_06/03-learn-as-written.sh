#!/usr/bin/env bash
# Clip 6.2: the planned failover of a read-scale group as the Learn page "Perform a planned
# manual failover of an availability group" writes it (section "Fail over the primary replica
# on a read-scale availability group", read on November 1, 2026), played literally from
# hadrlab2, the primary left by 02-planned.sh, back to hadrlab1: REQUIRED_SYNCHRONIZED_
# SECONDARIES_TO_COMMIT = 1 (step 3); OFFLINE on the primary and on hadrlab3, the secondary
# that does not take part (step 4); FORCE_FAILOVER_ALLOW_DATA_LOSS on hadrlab1 (step 5);
# SET (ROLE = SECONDARY) on the old primary only (step 6: "run the following command on the
# SQL Server instance that hosts the old primary replica"); SET HADR RESUME on the new primary
# (step 7). Thirty seconds later: the two secondaries do not synchronize, and the database of
# the new primary refuses reads and writes (Msg 988), because the setting is still 1 and no
# secondary is synchronized. The repair: SET (ROLE = SECONDARY) on hadrlab3, which step 4 had
# set offline (RESOLVING), RESUME on each secondary once its copy shows as suspended (at most a
# minute each), the setting back to 0. Leaves hadrlab1 primary. Run after 02-planned.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
mine() {
    sql $1 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  ', @@SERVERNAME, N': ', rs.role_desc, N', ', rs.operational_state_desc, N', ',
              ISNULL(d.synchronization_state_desc, N'-'), N', suspended ', ISNULL(CAST(d.is_suspended AS varchar(1)), N'-'),
              IIF(d.is_suspended = 1, N' (' + d.suspend_reason_desc + N')', N''))
FROM sys.dm_hadr_availability_replica_states AS rs
LEFT JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = rs.replica_id AND d.is_local = 1
     AND d.database_id = DB_ID(N'm06_registration')
WHERE rs.is_local = 1;" 2>&1 | grep -v '^ *$' || true
}
all() { for n in $nodes; do mine $n; done; }
step() { local n=$1; shift; echo "  $n: $*"; sql $n -Q "$*"; }
echo "== Learn, steps 3 to 7"
step hadrlab2 "ALTER AVAILABILITY GROUP AgPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1);"
step hadrlab2 "ALTER AVAILABILITY GROUP AgPacha OFFLINE;"
step hadrlab3 "ALTER AVAILABILITY GROUP AgPacha OFFLINE;"
step hadrlab1 "ALTER AVAILABILITY GROUP AgPacha FORCE_FAILOVER_ALLOW_DATA_LOSS;"
step hadrlab2 "ALTER AVAILABILITY GROUP AgPacha SET (ROLE = SECONDARY);"
step hadrlab1 "ALTER DATABASE m06_registration SET HADR RESUME;"
echo
echo "== 30 seconds later"
sleep 30
all
echo "  hadrlab1: SELECT, then INSERT"
sql hadrlab1 -Q "SELECT COUNT(*) FROM m06_registration.dbo.Registration;" 2>&1 | grep -v '^ *$' | sed 's/^/    /' || true
sql hadrlab1 -Q "INSERT m06_registration.dbo.Registration (label, email) VALUES ('learn', 'learn@pachadata.example');" 2>&1 \
    | grep -v '^ *$' | sed 's/^/    /' || true
echo
echo "== the repair: SET (ROLE = SECONDARY) on hadrlab3, then RESUME on each secondary once suspended"
step hadrlab3 "ALTER AVAILABILITY GROUP AgPacha SET (ROLE = SECONDARY);"
for n in hadrlab2 hadrlab3; do
    s=""
    for i in $(seq 1 60); do
        s=$(mine $n)
        case $s in *"suspended 1"*) break ;; esac
        sleep 1
    done
    echo "$s"
    case $s in *"suspended 1"*) ;; *) echo "$n is not suspended after a minute" >&2; exit 1 ;; esac
    step $n "ALTER DATABASE m06_registration SET HADR RESUME;"
done
for i in $(seq 1 60); do
    late=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.dm_hadr_database_replica_states AS d
        JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
        WHERE d.is_local = 0 AND d.database_id = DB_ID(N'm06_registration')
          AND NOT (d.synchronization_state_desc = N'SYNCHRONIZED'
                   OR (ar.availability_mode_desc = N'ASYNCHRONOUS_COMMIT' AND d.synchronization_state_desc = N'SYNCHRONIZING'));" \
        2>/dev/null | tr -d '[:space:]')
    [ "$late" = 0 ] && break
    sql hadrlab1 -Q "USE m06_registration; CHECKPOINT;" >/dev/null 2>&1 || true; sleep 1
done
[ "$late" = 0 ] || { echo "the secondaries have not caught up within a minute" >&2; exit 1; }
step hadrlab1 "ALTER AVAILABILITY GROUP AgPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0);"
sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, rs.role_desc AS role, d.synchronization_state_desc AS sync, d.is_suspended AS suspended
FROM sys.availability_replicas AS ar
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id AND d.database_id = DB_ID(N'm06_registration')
ORDER BY ar.replica_server_name;
SELECT COUNT(*) AS rows_on_hadrlab1 FROM m06_registration.dbo.Registration;"
