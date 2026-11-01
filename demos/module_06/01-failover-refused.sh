#!/usr/bin/env bash
# Clip 6.1: the failover that SQL Server refuses without a cluster. On hadrlab2, the
# synchronous secondary, SYNCHRONIZED: ALTER AVAILABILITY GROUP AgPacha FAILOVER, the planned
# failover of a group under a cluster, fails with Msg 47122 ("Only force failover is
# supported"). The group is read before and after: nothing has moved. Run after 00-setup.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
state() {
    sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT g.name AS ag, g.cluster_type_desc AS cluster_type, ar.replica_server_name AS replica, rs.role_desc AS role,
       ar.availability_mode_desc AS mode, d.synchronization_state_desc AS sync
FROM sys.availability_groups AS g
JOIN sys.availability_replicas AS ar ON ar.group_id = g.group_id
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id AND d.database_id = DB_ID(N'm06_registration')
WHERE g.name = N'AgPacha' ORDER BY ar.replica_server_name;"
}
echo "== hadrlab1, the group"
state
echo
echo "== hadrlab2: ALTER AVAILABILITY GROUP AgPacha FAILOVER"
sql hadrlab2 -Q "ALTER AVAILABILITY GROUP AgPacha FAILOVER;" 2>&1 || true
echo
echo "== hadrlab1, the group after"
state
