#!/usr/bin/env bash
# Clip 14.2, end: what step 8 of the page is for. The failover of 02-failover.sh again, from
# hadrlab1 to hadrlab3, but step 8 forgotten: REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT stays
# 1 on the side of AgSite1. Nothing shows while hadrlab1 is the forwarder. Then the failback
# (steps 4, 6, 7, 8 from hadrlab3): back on hadrlab1, every write is refused with Msg 988
# until hadrlab3 is connected and synchronized again, read every second, a minute at most.
# Then the same once more, with REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0 sent on hadrlab1
# right after the failback: the next write passes. Appends the measure to
# evidence/module_14.md. Leaves hadrlab1 global primary, DagPacha in ASYNCHRONOUS_COMMIT, the
# setting at 0 on both sides. Run after 02-failover.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
dag_sync() {  # the synchronization of the other site's copy, read on the global primary
    sql $1 -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL((SELECT d.synchronization_state_desc FROM sys.dm_hadr_database_replica_states AS d
        JOIN sys.availability_groups AS g ON g.group_id = d.group_id AND g.name = N'DagPacha'
        WHERE d.is_local = 0 AND d.database_id = DB_ID(N'm14_registration')), N'none');" | tr -d '[:space:]'
}
until_synchronized() {
    local s
    # An idle global primary leaves the copy SYNCHRONIZING (02-failover.sh): a CHECKPOINT
    # writes the log that moves it.
    for i in $(seq 1 60); do
        s=$(dag_sync $1); [ "$s" = SYNCHRONIZED ] && return 0
        sql $1 -Q "USE m14_registration; CHECKPOINT;" > /dev/null; sleep 1
    done
    echo "DagPacha is $s on $1 after a minute" >&2; exit 1
}
setting() {  # REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT of DagPacha on the three instances
    for n in $nodes; do
        sql $n -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'  ', @@SERVERNAME, N': ', ISNULL(CONVERT(varchar(3),
            (SELECT required_synchronized_secondaries_to_commit FROM sys.availability_groups WHERE name = N'DagPacha')), N'-'));"
    done
}
write() {  # one row on hadrlab1: the number of rows, or the error
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; INSERT m14_registration.dbo.Registration (label, email) VALUES ('$1', 'probe@pachadata.example');
        SELECT CONCAT(N'committed, ', COUNT(*), N' rows') FROM m14_registration.dbo.Registration;" 2>&1 \
        | grep -v '^ *$' | head -2 | tr '\n' ' ' | cut -c1-140 || true
}
to_site2() {  # steps 2 to 7, hadrlab1 to hadrlab3, without step 8
    for n in hadrlab1 hadrlab3; do
        sql $n -Q "ALTER AVAILABILITY GROUP [DagPacha] MODIFY AVAILABILITY GROUP ON
 'AgSite1' WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT), 'AgSite2' WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT);"
    done
    until_synchronized hadrlab1
    sql hadrlab1 -Q "ALTER AVAILABILITY GROUP DagPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1);"
    sql hadrlab1 -Q "ALTER AVAILABILITY GROUP DagPacha SET (ROLE = SECONDARY);"
    sql hadrlab3 -Q "ALTER AVAILABILITY GROUP DagPacha FORCE_FAILOVER_ALLOW_DATA_LOSS;"
}
to_site1() {  # steps 3 to 8, hadrlab3 back to hadrlab1
    until_synchronized hadrlab3
    sql hadrlab3 -Q "ALTER AVAILABILITY GROUP DagPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1);"
    sql hadrlab3 -Q "ALTER AVAILABILITY GROUP DagPacha SET (ROLE = SECONDARY);"
    sql hadrlab1 -Q "ALTER AVAILABILITY GROUP DagPacha FORCE_FAILOVER_ALLOW_DATA_LOSS;"
    sql hadrlab3 -Q "ALTER AVAILABILITY GROUP DagPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0);"
}
echo "== 1. failover to hadrlab3, steps 2 to 7 of the page, step 8 forgotten"
to_site2
echo "  hadrlab3 global primary; the setting of DagPacha:"
setting
echo
echo "== 2. failback to hadrlab1 (steps 3 to 8 from hadrlab3), then a write on hadrlab1 every second"
to_site1
t0=$(date +%s.%N)
refused=0
for i in $(seq 1 60); do
    r=$(write "after the failback")
    t=$(awk -v s=$t0 -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }')
    echo "  +$t s: $r"
    case $r in committed*) break ;; *"Msg 988,"*) refused=$((refused + 1)) ;; *) echo "unexpected: $r" >&2; exit 1 ;; esac
    sleep 1
done
case $r in committed*) ;; *) echo "hadrlab1 still refuses writes a minute after the failback" >&2; exit 1 ;; esac
first_ok=$t
echo "  hadrlab1 sees AgSite2: $(dag_sync hadrlab1); the setting:"
setting
echo
echo "== 3. the same again, and on hadrlab1, right after the failback, the setting back to 0"
to_site2
to_site1
r0=$(write "before the setting")
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP DagPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0);"
r1=$(write "after the setting")
echo "  before: $r0"
echo "  after REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0: $r1"
case $r1 in committed*) ;; *) echo "hadrlab1 refuses the write with the setting at 0" >&2; exit 1 ;; esac
until_synchronized hadrlab1
for n in hadrlab1 hadrlab3; do
    sql $n -Q "ALTER AVAILABILITY GROUP DagPacha MODIFY AVAILABILITY GROUP ON
 'AgSite1' WITH (AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT), 'AgSite2' WITH (AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT);"
done
setting
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 14, step 8 of the failover of DagPacha skipped (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT left at 1 on hadrlab1): after the failback, writes on hadrlab1 refused with Msg 988 ($refused tries, one a second) until the first one accepted $first_ok s after the failback; with the setting sent back to 0, the next write accepted; three containers on one host" >> evidence/module_14.md
