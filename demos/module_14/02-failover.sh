#!/usr/bin/env bash
# Clip 14.2: the failover of the distributed group without data loss, then the failback, both
# by the steps of the Learn page "Configure a distributed Always On availability group",
# section "Fail over a distributed availability group", tab "SQL Server 2022 and later", run as
# written (its queries included, with the names of the lab), while an application writes on
# the global primary:
#   0. ALTER AVAILABILITY GROUP ... FAILOVER, refused: the page says that a distributed group
#      only takes FORCE_FAILOVER_ALLOW_DATA_LOSS;
#   1. the primaries of AgSite1 and AgSite2 are in SYNCHRONOUS_COMMIT (read on both);
#   2. DagPacha set to SYNCHRONOUS_COMMIT on the global primary and on the forwarder;
#   3. read on the global primary until DagPacha is SYNCHRONIZED;
#   4. on the global primary, REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1;
#   5. the state of the three groups, read on the global primary and on the forwarder;
#   6. on the global primary, SET (ROLE = SECONDARY): the writer stops there;
#   7. on the forwarder, FORCE_FAILOVER_ALLOW_DATA_LOSS;
#   8. on the new forwarder, REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0.
# Then the rows the writer saw committed are counted on the new global primary, the state of
# the three instances is read, and the time until the old site is SYNCHRONIZED again is
# measured: until then, the new global primary commits without a copy on the other site. The
# failback runs the same steps the other way, and ends with the optional step 9 (back to
# ASYNCHRONOUS_COMMIT). Appends the measures to evidence/module_14.md. Leaves hadrlab1 global
# primary, as 01-two-sites.sh left it. Run after 01-two-sites.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
writer_log=$(mktemp)
trap 'rm -f "$writer_log"' EXIT
t0=""
elapsed() { awk -v s=$t0 -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }'; }
state() {  # the groups seen from one instance: role, connection, synchronization of each copy
    sql $1 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  ', @@SERVERNAME, N' sees ', g.name, N': ', ar.replica_server_name, N' ', ISNULL(rs.role_desc, N'-'), N', ',
              ISNULL(rs.connected_state_desc, N'-'), N', ', ar.availability_mode_desc,
              ISNULL(N', copy ' + d.synchronization_state_desc, N''))
FROM sys.availability_groups AS g
JOIN sys.availability_replicas AS ar ON ar.group_id = g.group_id
LEFT JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id AND rs.group_id = g.group_id
LEFT JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id AND d.group_id = g.group_id
     AND d.database_id = DB_ID(N'm14_registration')
WHERE rs.role_desc IS NOT NULL
ORDER BY g.is_distributed, g.name, ar.replica_server_name;"
}
dag_sync() {  # the synchronization of the other site's copy, read on the global primary
    sql $1 -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL((SELECT d.synchronization_state_desc FROM sys.dm_hadr_database_replica_states AS d
        JOIN sys.availability_groups AS g ON g.group_id = d.group_id AND g.name = N'DagPacha'
        WHERE d.is_local = 0 AND d.database_id = DB_ID(N'm14_registration')), N'none');" | tr -d '[:space:]'
}
failover() {  # global primary, forwarder: steps 1 to 8 of the page
    local gp=$1 fw=$2 s
    echo "== 1. $gp and $fw: the primaries of the two groups in SYNCHRONOUS_COMMIT?"
    for n in $gp $fw; do
        sql $n -h -1 -s ' ' -Q "SET NOCOUNT ON;
SELECT DISTINCT N'  ' + @@SERVERNAME + N':', ag.name AS [Availability Group],
                ar.replica_server_name AS [Replica],
                ar.availability_mode_desc AS [Availability Mode]
FROM sys.availability_replicas AS ar
     INNER JOIN
     sys.availability_groups AS ag
     ON ar.group_id = ag.group_id
     INNER JOIN
     sys.dm_hadr_database_replica_states AS rs
     ON ar.group_id = rs.group_id
        AND ar.replica_id = rs.replica_id
WHERE ag.name IN ('AgSite1', 'AgSite2')
      AND rs.is_primary_replica = 1
ORDER BY [Availability Group];"
    done
    echo "== 2. $gp and $fw: DagPacha in SYNCHRONOUS_COMMIT"
    for n in $gp $fw; do
        sql $n -Q "ALTER AVAILABILITY GROUP [DagPacha] MODIFY AVAILABILITY GROUP ON
 'AgSite1' WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT),
 'AgSite2' WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT);"
    done
    echo "== 3. $gp: until DagPacha is SYNCHRONIZED"
    # Measured: with nothing written on the global primary, the copy stays SYNCHRONIZING for
    # more than a minute after step 2; the first log the primary writes makes it SYNCHRONIZED.
    # The page does not say it: after 5 seconds, a CHECKPOINT is sent, and the script says so.
    for i in $(seq 1 60); do
        s=$(dag_sync $gp)
        [ "$s" = SYNCHRONIZED ] && break
        if [ $i = 5 ]; then
            echo "  $gp: still $s after 5 s, nothing written: CHECKPOINT"
            sql $gp -Q "USE m14_registration; CHECKPOINT;" > /dev/null
        fi
        sleep 1
    done
    [ "$s" = SYNCHRONIZED ] || { echo "DagPacha is $s a minute after step 2" >&2; exit 1; }
    sql $gp -h -1 -s ' ' -Q "SET NOCOUNT ON; SELECT N' ', ag.name, db_name(drs.database_id) AS database_name,
       drs.synchronization_state_desc, drs.last_hardened_lsn
FROM sys.dm_hadr_database_replica_states AS drs
     INNER JOIN sys.availability_groups AS ag ON drs.group_id = ag.group_id
WHERE ag.name = 'DagPacha';"
    echo "== 4. $gp: REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1"
    sql $gp -Q "ALTER AVAILABILITY GROUP DagPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1);"
    echo "== 5. $gp and $fw: every copy healthy?"
    for n in $gp $fw; do
        sql $n -h -1 -s ' ' -Q "SET NOCOUNT ON; SELECT N'  ' + @@SERVERNAME + N':', ag.name AS [AG Name],
       db_name(drs.database_id) AS database_name,
       ar.replica_server_name AS [replica],
       drs.synchronization_state_desc,
       drs.last_hardened_lsn
FROM sys.dm_hadr_database_replica_states AS drs
     INNER JOIN sys.availability_groups AS ag ON drs.group_id = ag.group_id
     INNER JOIN sys.availability_replicas AS ar ON drs.replica_id = ar.replica_id
        AND drs.replica_id = ar.replica_id
WHERE ag.name IN ('AgSite1', 'AgSite2', 'DagPacha');"
    done
    echo "== 6. $gp: SET (ROLE = SECONDARY)"
    t0=$(date +%s.%N)
    sql $gp -Q "ALTER AVAILABILITY GROUP DagPacha SET (ROLE = SECONDARY);"
    echo "== 7. $fw: FORCE_FAILOVER_ALLOW_DATA_LOSS (+$(elapsed) s)"
    sql $fw -Q "ALTER AVAILABILITY GROUP DagPacha FORCE_FAILOVER_ALLOW_DATA_LOSS;"
    sql $fw -h -1 -Q "SET NOCOUNT ON; INSERT m14_registration.dbo.Registration (label, email) VALUES ('control', 'control@pachadata.example');"
    took=$(elapsed)
    echo "  $fw: a control row committed, $took s after step 6"
    echo "== 8. $gp: REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0"
    sql $gp -Q "ALTER AVAILABILITY GROUP DagPacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0);"
}
relink() {  # new global primary: the time until the other site is SYNCHRONIZED again
    local s
    for i in $(seq 1 120); do
        s=$(dag_sync $1)
        [ "$s" = SYNCHRONIZED ] && break
        sleep 0.5
    done
    [ "$s" = SYNCHRONIZED ] || { echo "the other site is $s a minute after the failover" >&2; exit 1; }
    elapsed
}
echo "== 0. hadrlab3: ALTER AVAILABILITY GROUP DagPacha FAILOVER"
if out=$(sql hadrlab3 -Q "ALTER AVAILABILITY GROUP DagPacha FAILOVER;" 2>&1); then
    echo "FAILOVER passed on a distributed group" >&2; exit 1
fi
printf '%s\n' "$out" | grep -v '^ *$' | sed 's/^/  /'
echo
echo "== the writer starts on hadrlab1 (one row every 100 ms, until its first error, a minute at most)"
timeout 60 bash -c ". setup/lib.sh; sql hadrlab1 -h -1 -Q \"SET NOCOUNT ON; DECLARE @i int = 0, @id int;
WHILE @i < 500 BEGIN
    INSERT m14_registration.dbo.Registration (label, email) VALUES ('writer', CONCAT('writer', @i, '@pachadata.example'));
    SET @id = SCOPE_IDENTITY(); RAISERROR('committed %d', 0, 1, @id) WITH NOWAIT;
    SET @i += 1; WAITFOR DELAY '00:00:00.100';
END;\"" > "$writer_log" 2>&1 &
writer=$!
sleep 2
failover hadrlab1 hadrlab3
wait $writer || true
n_ok=$(grep -c committed "$writer_log" || true)
last=$(grep committed "$writer_log" | tail -1 | grep -o '[0-9]*$')
echo "  the writer: $n_ok rows committed on hadrlab1, the last one $last, then:"
grep -v committed "$writer_log" | grep -v '^ *$' | head -2 | sed 's/^/    /' || true
back=$(relink hadrlab3)
echo "  hadrlab3: AgSite1 SYNCHRONIZED again $back s after step 6"
echo
echo "== hadrlab3, the new global primary: are the writer's rows there?"
lost=$(sql hadrlab3 -h -1 -Q "SET NOCOUNT ON; SELECT $n_ok - COUNT(*) FROM m14_registration.dbo.Registration WHERE label = 'writer' AND id <= $last;" | tr -d '[:space:]')
sql hadrlab3 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'  ', label, N': ', COUNT(*), N' rows') FROM m14_registration.dbo.Registration GROUP BY label ORDER BY MIN(id);"
echo "  rows the writer saw committed and missing on hadrlab3: $lost"
echo
echo "== the state after the failover"
for n in $nodes; do state $n; done
failed_over=$took
echo
echo "== the failback, by the same steps"
failover hadrlab3 hadrlab1
back2=$(relink hadrlab1)
echo "  hadrlab1: AgSite2 SYNCHRONIZED again $back2 s after step 6"
echo "== 9. hadrlab1 and hadrlab3: DagPacha back to ASYNCHRONOUS_COMMIT"
for n in hadrlab1 hadrlab3; do
    sql $n -Q "ALTER AVAILABILITY GROUP DagPacha MODIFY AVAILABILITY GROUP ON
 'AgSite1' WITH (AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT),
 'AgSite2' WITH (AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT);"
done
echo
echo "== the state after the failback"
for n in $nodes; do state $n; done
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; INSERT m14_registration.dbo.Registration (label, email) VALUES ('after the failback', 'back@pachadata.example');
SELECT CONCAT(N'  hadrlab1: ', label, N': ', COUNT(*), N' rows') FROM m14_registration.dbo.Registration GROUP BY label ORDER BY MIN(id);"
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 14, planned failover of the distributed group DagPacha from AgSite1 (hadrlab1) to AgSite2 (hadrlab3) by the steps of Learn (SQL Server 2022 and later), a writer on hadrlab1: $lost rows lost of $n_ok committed, a write accepted on hadrlab3 $failed_over s after SET (ROLE = SECONDARY), AgSite1 SYNCHRONIZED again after $back s; failback to hadrlab1 by the same steps: a write accepted after $took s, AgSite2 SYNCHRONIZED again after $back2 s; three containers on one host" >> evidence/module_14.md
