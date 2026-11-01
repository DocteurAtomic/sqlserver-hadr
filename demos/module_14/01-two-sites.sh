#!/usr/bin/env bash
# Clip 14.1: two groups, two sites, and the distributed group between them, as the Learn page
# "Configure a distributed Always On availability group" writes them, statement by statement,
# with the names of the lab. Where the page does not hold without a cluster, the statement as
# written is run first and its refusal shown, then the change that makes it pass:
#   1. the endpoints: the page asks for LISTENER_IP = ALL; read on the three instances;
#   2. AgSite1 (hadrlab1 and hadrlab2, synchronous commit, automatic seeding), as written:
#      Msg 19417 (no CLUSTER_TYPE: the group asks for a Windows cluster); with
#      CLUSTER_TYPE = NONE: Msg 47101 (FAILOVER_MODE = AUTOMATIC); with MANUAL: created; the
#      JOIN of hadrlab2 as written: Msg 19417; with CLUSTER_TYPE = NONE (join_ag): joined;
#   3. AgSite2 on hadrlab3 alone, without a database; no listener for either group: the page
#      asks for one, the distributed group is given the endpoint of each primary instead;
#   4. DagPacha WITH (DISTRIBUTED) on hadrlab1, its JOIN on hadrlab3, automatic seeding, as
#      written; the time until hadrlab3 has its copy;
#   5. the state on the three instances, and a row written on hadrlab1: it reaches hadrlab3
#      (same last hardened LSN), where the database cannot be read (Msg 976).
# Appends the seeding time to evidence/module_14.md. Leaves DagPacha in place for
# 02-failover.sh. Run after 00-setup.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
refused() {  # instance, Msg number expected; the batch on stdin must fail with that message
    local n=$1 msg=$2 out
    if out=$(sql "$n" 2>&1); then echo "  expected Msg $msg on $n, the statement passed" >&2; exit 1; fi
    case $out in
        *"Msg $msg,"*) printf '%s\n' "$out" | grep -v '^ *$' | head -2 | sed 's/^/  /' ;;
        *) printf '%s\n' "$out" >&2; exit 1 ;;
    esac
}
agsite1() {  # Learn's ag1 with the names of the lab; $1 = WITH clause, $2 = failover mode
    cat <<SQL
CREATE AVAILABILITY GROUP [AgSite1]
$1
FOR DATABASE m14_registration
REPLICA ON N'hadrlab1' WITH (ENDPOINT_URL = N'TCP://hadrlab1:5022',
    FAILOVER_MODE = $2,
    AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
    BACKUP_PRIORITY = 50,
    SECONDARY_ROLE(ALLOW_CONNECTIONS = NO),
    SEEDING_MODE = AUTOMATIC),
N'hadrlab2' WITH (ENDPOINT_URL = N'TCP://hadrlab2:5022',
    FAILOVER_MODE = $2,
    AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
    BACKUP_PRIORITY = 50,
    SECONDARY_ROLE(ALLOW_CONNECTIONS = NO),
    SEEDING_MODE = AUTOMATIC);
SQL
}
members() {  # the AVAILABILITY GROUP ON clause of the distributed group, as the page writes it
    cat <<'SQL'
   AVAILABILITY GROUP ON
      'AgSite1' WITH
      (
         LISTENER_URL = 'tcp://hadrlab1:5022',
         AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
         FAILOVER_MODE = MANUAL,
         SEEDING_MODE = AUTOMATIC
      ),
      'AgSite2' WITH
      (
         LISTENER_URL = 'tcp://hadrlab3:5022',
         AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
         FAILOVER_MODE = MANUAL,
         SEEDING_MODE = AUTOMATIC
      );
SQL
}
echo "== 1. the database mirroring endpoints (the page asks for LISTENER_IP = ALL)"
for n in $nodes; do
    sql $n -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'  ', @@SERVERNAME, N': ', t.name COLLATE DATABASE_DEFAULT, N', port ', t.port, N', listener IP ',
        ISNULL(CONVERT(varchar(40), t.ip_address), N'ALL'), N', ', d.connection_auth_desc COLLATE DATABASE_DEFAULT, N', ', t.state_desc COLLATE DATABASE_DEFAULT)
        FROM sys.tcp_endpoints AS t JOIN sys.database_mirroring_endpoints AS d ON d.endpoint_id = t.endpoint_id;"
done
echo
echo "== 2. hadrlab1: AgSite1 as the page writes ag1"
agsite1 "" AUTOMATIC | refused hadrlab1 19417
echo "   with CLUSTER_TYPE = NONE:"
agsite1 "WITH (CLUSTER_TYPE = NONE)" AUTOMATIC | refused hadrlab1 47101
echo "   with CLUSTER_TYPE = NONE and FAILOVER_MODE = MANUAL:"
agsite1 "WITH (CLUSTER_TYPE = NONE)" MANUAL | sql hadrlab1
echo "  AgSite1 created on hadrlab1"
echo "   hadrlab2: the JOIN as the page writes it"
printf 'ALTER AVAILABILITY GROUP [AgSite1] JOIN\nALTER AVAILABILITY GROUP [AgSite1] GRANT CREATE ANY DATABASE\n' | refused hadrlab2 19417
echo "   hadrlab2: JOIN WITH (CLUSTER_TYPE = NONE), then GRANT CREATE ANY DATABASE"
join_ag hadrlab2 AgSite1
wait_ag_database hadrlab1 AgSite1 m14_registration 120 | sed 's/^/  /'
echo
echo "== 3. hadrlab3: AgSite2, one replica, no database (the page's ag2, without server4)"
sql hadrlab3 <<'SQL'
CREATE AVAILABILITY GROUP [AgSite2]
WITH (CLUSTER_TYPE = NONE)
FOR
REPLICA ON N'hadrlab3' WITH (ENDPOINT_URL = N'TCP://hadrlab3:5022',
    FAILOVER_MODE = MANUAL,
    AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
    BACKUP_PRIORITY = 50,
    SECONDARY_ROLE(ALLOW_CONNECTIONS = NO),
    SEEDING_MODE = AUTOMATIC);
SQL
echo "  AgSite2 created on hadrlab3; no listener on either group: LISTENER_URL takes the endpoint of each primary"
echo
echo "== 4. hadrlab1: CREATE AVAILABILITY GROUP [DagPacha] WITH (DISTRIBUTED), then the JOIN on hadrlab3"
{ echo "CREATE AVAILABILITY GROUP [DagPacha]"; echo "   WITH (DISTRIBUTED)"; members; } | sql hadrlab1
t0=$(date +%s.%N)
# A distributed group of the same name dropped a moment before can still be leaving hadrlab3
# (Msg 41180, as join_ag knows it): the JOIN is tried again every 2 seconds on that error only.
for i in $(seq 1 30); do
    if out=$({ echo "ALTER AVAILABILITY GROUP [DagPacha]"; echo "   JOIN"; members; } | sql hadrlab3 2>&1); then break; fi
    case $out in *"Msg 41180,"*) sleep 2 ;; *) echo "$out" >&2; exit 1 ;; esac
done
# Read on the global primary: hadrlab3's copy, once seeded, is SYNCHRONIZING (asynchronous).
for i in $(seq 1 120); do
    s=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT d.synchronization_state_desc FROM sys.dm_hadr_database_replica_states AS d
        JOIN sys.availability_groups AS g ON g.group_id = d.group_id AND g.name = N'DagPacha'
        WHERE d.is_local = 0 AND d.database_id = DB_ID(N'm14_registration');" | tr -d '[:space:]')
    o=$(sql hadrlab3 -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL(CONVERT(varchar(20), DATABASEPROPERTYEX(N'm14_registration', 'Status')), 'missing');" | tr -d '[:space:]')
    case "$s $o" in "SYNCHRONIZING ONLINE"|"SYNCHRONIZED ONLINE") break ;; esac
    sleep 1
done
seeded=$(awk -v s=$t0 -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }')
case "$s $o" in "SYNCHRONIZING ONLINE"|"SYNCHRONIZED ONLINE") ;; *) echo "hadrlab3 has no copy two minutes after the JOIN: $s $o" >&2; exit 1 ;; esac
echo "  hadrlab3 joined; its copy of m14_registration $s for DagPacha, $seeded s after the JOIN"
echo
echo "== 5. the state, instance by instance"
for n in $nodes; do
    echo "-- $n"
    sql $n -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  ', g.name, IIF(g.is_distributed = 1, N' (distributed)', N''), N': ', ar.replica_server_name, N' ',
              ISNULL(rs.role_desc, N'(no state here)'), N', ', ar.availability_mode_desc,
              IIF(rs.role_desc IS NULL, N'', N', ' + rs.connected_state_desc + N', ' + rs.synchronization_health_desc))
FROM sys.availability_groups AS g
JOIN sys.availability_replicas AS ar ON ar.group_id = g.group_id
LEFT JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id AND rs.group_id = g.group_id
ORDER BY g.is_distributed, g.name, ar.replica_server_name;"
done
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; INSERT m14_registration.dbo.Registration (label, email) VALUES ('site 1', 'site1@pachadata.example');
SELECT CONCAT(N'  hadrlab1: one row written, ', COUNT(*), N' registrations') FROM m14_registration.dbo.Registration;"
for i in $(seq 1 30); do
    lsn=$(sql hadrlab1 -h -1 -s '|' -Q "SET NOCOUNT ON; SELECT CONCAT(p.last_hardened_lsn, N'|', d.last_hardened_lsn, N'|', d.synchronization_state_desc)
        FROM sys.dm_hadr_database_replica_states AS d
        JOIN sys.availability_groups AS g ON g.group_id = d.group_id AND g.name = N'DagPacha'
        JOIN sys.dm_hadr_database_replica_states AS p ON p.database_id = d.database_id AND p.is_local = 1
        WHERE d.is_local = 0 AND d.database_id = DB_ID(N'm14_registration');" | tr -d '[:space:]')
    p=${lsn%%|*} r=${lsn#*|}; r=${r%%|*}
    [ -n "$p" ] && [ "$p" = "$r" ] && break
    sql hadrlab1 -Q "USE m14_registration; CHECKPOINT;" > /dev/null; sleep 1
done
echo "  hadrlab1, last hardened LSN: its own $p, AgSite2's $r (${lsn##*|})"
echo "  hadrlab3, SELECT COUNT(*):"
echo "SELECT COUNT(*) FROM m14_registration.dbo.Registration;" | refused hadrlab3 976
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 14, distributed availability group DagPacha between AgSite1 (hadrlab1, hadrlab2) and AgSite2 (hadrlab3), no cluster, no listener, asynchronous: hadrlab3 had its copy of m14_registration (automatic seeding, 100 rows) $seeded s after its JOIN; three containers on one host" >> evidence/module_14.md
