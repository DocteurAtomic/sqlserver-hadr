#!/usr/bin/env bash
# Clip 10.1: remove a replica from the group and add it back.
#   1. hadrlab1: ALTER AVAILABILITY GROUP AgPacha REMOVE REPLICA ON 'hadrlab3'; the group as
#      hadrlab1 sees it, then as hadrlab3 sees it, right away and 30 seconds later: without a
#      cluster, hadrlab3 keeps the group, SECONDARY, then DISCONNECTED, and its copies stay
#      ONLINE, read-only, NOT SYNCHRONIZING.
#   2. hadrlab1: ADD REPLICA ON 'hadrlab3'; hadrlab3: JOIN, refused (Msg 41106, a replica of the
#      group already exists on this instance).
#   3. hadrlab3: DROP AVAILABILITY GROUP AgPacha, which leaves its copies in RESTORING; then the
#      JOIN again (setup/lib.sh join_ag, which tries again on Msg 41180 while the group is still
#      being dropped) and the wait for the copies (wait_ag_database). The replica takes its
#      RESTORING copies back: no new seeding backup appears in msdb of hadrlab1.
# Run after 01-database.sh (m10_registration and m10_archive in AgPacha).
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
group_on() {  # the group and the local copies, as an instance sees them
    sql $1 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  ', @@SERVERNAME, N' sees ', ar.replica_server_name, N': ', ISNULL(rs.role_desc COLLATE DATABASE_DEFAULT, N'-'), N' ',
              ISNULL(rs.connected_state_desc COLLATE DATABASE_DEFAULT, N'-'), N' ', ISNULL(rs.synchronization_health_desc COLLATE DATABASE_DEFAULT, N'-'))
FROM sys.availability_groups AS g
JOIN sys.availability_replicas AS ar ON ar.group_id = g.group_id
LEFT JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
WHERE g.name = N'AgPacha' ORDER BY ar.replica_server_name;
SELECT CONCAT(N'  ', @@SERVERNAME, N' groups: ', COUNT(*)) FROM sys.availability_groups;
SELECT CONCAT(N'  ', @@SERVERNAME, N' copy of ', d.name, N': ', d.state_desc COLLATE DATABASE_DEFAULT, N', ',
              CAST(DATABASEPROPERTYEX(d.name, 'Updateability') AS nvarchar(20)), N', ',
              ISNULL(rs.synchronization_state_desc COLLATE DATABASE_DEFAULT, N'outside the group'))
FROM sys.databases AS d
LEFT JOIN sys.dm_hadr_database_replica_states AS rs ON rs.database_id = d.database_id AND rs.is_local = 1
WHERE d.name LIKE N'm10[_]%' ORDER BY d.name;"
}
seedings() {
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  seeding backups in msdb of hadrlab1: ', COUNT(*))
FROM msdb.dbo.backupset AS b JOIN msdb.dbo.backupmediafamily AS m ON m.media_set_id = b.media_set_id
WHERE b.database_name LIKE N'm10[_]%' AND TRY_CAST(m.physical_device_name AS uniqueidentifier) IS NOT NULL;"
}
out=$(mktemp)
trap 'rm -f "$out"' EXIT
seedings
echo "== 1. hadrlab1: REMOVE REPLICA ON 'hadrlab3'"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha REMOVE REPLICA ON N'hadrlab3';"
sleep 2
group_on hadrlab1
group_on hadrlab3
echo "-- 30 s later"
sleep 30
group_on hadrlab3
echo
echo "== 2. hadrlab1: ADD REPLICA ON 'hadrlab3'; hadrlab3: JOIN"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha ADD REPLICA ON N'hadrlab3' WITH (
    ENDPOINT_URL = N'tcp://hadrlab3:5022', AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
    FAILOVER_MODE = MANUAL, SEEDING_MODE = AUTOMATIC);"
if sql hadrlab3 -Q "ALTER AVAILABILITY GROUP AgPacha JOIN WITH (CLUSTER_TYPE = NONE);" > "$out" 2>&1; then
    cat "$out"; rm -f "$out"
    echo "the JOIN was accepted: Msg 41106 expected" >&2; exit 1
fi
sed 's/^/  /' "$out"; rm -f "$out"
echo
echo "== 3. hadrlab3: DROP AVAILABILITY GROUP AgPacha, then JOIN"
sql hadrlab3 -Q "DROP AVAILABILITY GROUP AgPacha;"
group_on hadrlab3
t0=$(date +%s.%N)
join_ag hadrlab3 AgPacha
for db in m10_registration m10_archive; do wait_ag_database hadrlab1 AgPacha $db 120 hadrlab3; done
echo "  hadrlab3 back in the group after $(awk -v s=$t0 -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }') s"
group_on hadrlab1
seedings
