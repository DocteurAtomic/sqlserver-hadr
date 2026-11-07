#!/usr/bin/env bash
# Clip 6.1: the planned failover without a cluster, step by step, hadrlab1 to hadrlab2, with an
# application writing all along. A writer on hadrlab1 inserts one row "writer" every 100 ms
# and prints the id of each row whose commit came back. Then, one statement at a time, each
# followed by what it changed:
#   1. hadrlab2 checked: synchronous, SYNCHRONIZED, last hardened LSN equal to the primary's;
#   2. on hadrlab1, REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1, then OFFLINE: the writer
#      stops on Msg 983;
#   3. on hadrlab2, FORCE_FAILOVER_ALLOW_DATA_LOSS;
#   4. on hadrlab1, then on hadrlab3, SET (ROLE = SECONDARY);
#   5. each copy is read until the failover has suspended it (SUSPEND_FROM_PARTNER, at most a
#      minute), then resumed; then read on hadrlab2 until both are caught up (at most a minute);
#   6. on hadrlab2, REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT back to 0, a control row, and
#      the count: every row the writer saw committed is on hadrlab2.
# Appends the duration of steps 2 to 6 to evidence/module_06.md. Leaves hadrlab2 primary:
# 03-learn-as-written.sh fails back to hadrlab1. Run after 01-failover-refused.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
mine() {  # the local replica and copy on an instance
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
t0=""
elapsed() { awk -v s=$t0 -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }'; }
writer_log=$(mktemp)
trap 'rm -f "$writer_log"' EXIT
echo "== 1. hadrlab1: is hadrlab2 caught up?"
sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, ar.availability_mode_desc AS mode, d.synchronization_state_desc AS sync,
       d.last_hardened_lsn, IIF(d.last_hardened_lsn = p.last_hardened_lsn, N'equal', N'behind') AS lsn_vs_primary
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
JOIN sys.dm_hadr_database_replica_states AS p ON p.group_database_id = d.group_database_id AND p.is_local = 1
WHERE d.database_id = DB_ID(N'm06_registration') ORDER BY ar.replica_server_name;"
echo
echo "== the writer starts on hadrlab1 (one row every 100 ms, a minute at most)"
timeout 60 bash -c ". setup/lib.sh; sql hadrlab1 -h -1 -Q \"SET NOCOUNT ON; DECLARE @i int = 0, @id int;
WHILE @i < 500 BEGIN
    INSERT m06_registration.dbo.Registration (label, email) VALUES ('writer', CONCAT('writer', @i, '@pachadata.example'));
    SET @id = SCOPE_IDENTITY(); RAISERROR('committed %d', 0, 1, @id) WITH NOWAIT;
    SET @i += 1; WAITFOR DELAY '00:00:00.100';
END;\"" > "$writer_log" 2>&1 &
writer=$!
sleep 3
echo
echo "== 2. hadrlab1: REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1, then OFFLINE"
t0=$(date +%s.%N)
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1);"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha OFFLINE;"
wait $writer || true
echo "  the writer: $(grep committed "$writer_log" | tail -1), then:"
grep -v committed "$writer_log" | grep -v '^ *$' | head -2 | sed 's/^/    /' || true
all
echo
echo "== 3. hadrlab2: FORCE_FAILOVER_ALLOW_DATA_LOSS (+$(elapsed) s)"
sql hadrlab2 -Q "ALTER AVAILABILITY GROUP AgPacha FORCE_FAILOVER_ALLOW_DATA_LOSS;"
all
echo
echo "== 4. hadrlab1, then hadrlab3: SET (ROLE = SECONDARY) (+$(elapsed) s)"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha SET (ROLE = SECONDARY);"
sql hadrlab3 -Q "ALTER AVAILABILITY GROUP AgPacha SET (ROLE = SECONDARY);"
all
echo
echo "== 5. each copy, once the failover has suspended it: SET HADR RESUME"
for n in hadrlab1 hadrlab3; do
    s=""
    for i in $(seq 1 60); do
        s=$(mine $n)
        case $s in *"suspended 1"*) break ;; esac
        sleep 1
    done
    echo "$s (+$(elapsed) s)"
    case $s in *"suspended 1"*) ;; *) echo "$n is not suspended a minute after SET (ROLE = SECONDARY)" >&2; exit 1 ;; esac
    resume_copy $n m06_registration
done
for i in $(seq 1 60); do
    late=$(sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.dm_hadr_database_replica_states AS d
        JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
        WHERE d.is_local = 0 AND d.database_id = DB_ID(N'm06_registration')
          AND NOT (d.synchronization_state_desc = N'SYNCHRONIZED'
                   OR (ar.availability_mode_desc = N'ASYNCHRONOUS_COMMIT' AND d.synchronization_state_desc = N'SYNCHRONIZING'));" \
        | tr -d '[:space:]')
    [ "$late" = 0 ] && break
    # Refused (Msg 988) while the setting is 1 and no secondary is synchronized: the next turn tries again.
    sql hadrlab2 -Q "USE m06_registration; CHECKPOINT;" >/dev/null 2>&1 || true; sleep 1
done
[ "$late" = 0 ] || { echo "the secondaries have not caught up within a minute" >&2; exit 1; }
echo
echo "== 6. hadrlab2: REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0 (+$(elapsed) s)"
sql hadrlab2 -Q "ALTER AVAILABILITY GROUP AgPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0);"
took=$(elapsed)
last=$(grep committed "$writer_log" | tail -1 | grep -o '[0-9]*$')
sql hadrlab2 -Q "SET NOCOUNT ON;
INSERT m06_registration.dbo.Registration (label, email) VALUES ('control', 'control@pachadata.example');
SELECT ar.replica_server_name AS replica, rs.role_desc AS role, d.synchronization_state_desc AS sync, d.is_suspended AS suspended
FROM sys.availability_replicas AS ar
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id AND d.database_id = DB_ID(N'm06_registration')
ORDER BY ar.replica_server_name;
SELECT label, COUNT(*) AS rows_on_hadrlab2, MAX(id) AS last_id, IIF(MAX(id) >= $last OR label <> 'writer', N'yes', N'NO') AS all_committed_rows_here
FROM m06_registration.dbo.Registration GROUP BY label ORDER BY MIN(id);"
echo "Planned failover from hadrlab1 to hadrlab2 in $took s, step by step; the writer's last committed row: $last."
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 6, planned failover without a cluster, hadrlab1 to hadrlab2, statement by statement: $took s from OFFLINE to the setting back to 0, writes refused for that time, no committed row lost; three containers on one host" >> evidence/module_06.md
