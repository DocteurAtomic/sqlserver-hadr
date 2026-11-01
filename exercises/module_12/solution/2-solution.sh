#!/usr/bin/env bash
# Exercise of module 12, one solution. The diagnosis, which check.sh does not read:
#   - setup/ag-health.sql on hadrlab1: hadrlab3 DISCONNECTED in AgHealth, its send queue and both
#     estimates NULL (unknown), while the same instance is CONNECTED in AgPacha: its endpoint
#     works, the cause is in the configuration of AgHealth;
#   - AlwaysOn_health on hadrlab1 (demos/module_12/05-read-health.sh): ConnectFailed toward
#     tcp:hadrlab3,5023, error 10061 (connection refused), and the alwayson_ddl_executed event of
#     the ALTER AVAILABILITY GROUP ... MODIFY REPLICA that set this address;
#   - sys.availability_replicas on hadrlab1 gives tcp://hadrlab3:5023 for hadrlab3,
#     sys.tcp_endpoints on hadrlab3 gives port 5022 for its endpoint.
# The repair, on the primary: the address of hadrlab3 given back, then the wait until its copy
# of ex_health is caught up. Restarting the endpoint of hadrlab3, as the support's decision tree
# says for a disconnected replica, changes nothing here (and would cut AgPacha off for a moment).
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'hadrlab1: AgHealth looked for hadrlab3 at ', endpoint_url) FROM sys.availability_replicas AS ar
JOIN sys.availability_groups AS g ON g.group_id = ar.group_id WHERE g.name = N'AgHealth' AND ar.replica_server_name = N'hadrlab3';
ALTER AVAILABILITY GROUP AgHealth MODIFY REPLICA ON N'hadrlab3' WITH (ENDPOINT_URL = N'tcp://hadrlab3:5022');"
# hadrlab1 tries the new address at its next reconnection, up to half a minute later; while
# hadrlab3 was cut off, each automatic seeding check toward it ended FAILED ("Check If Seeding
# Needed", every 30 seconds), so the wait reads the state of the copy, not the seeding.
t0=$(date +%s)
for i in $(seq 1 120); do
    state=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(rs.connected_state_desc, N' ', d.synchronization_state_desc)
        FROM sys.availability_groups AS g JOIN sys.availability_replicas AS ar ON ar.group_id = g.group_id
        JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
        JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id AND d.database_id = DB_ID(N'ex_health')
        WHERE g.name = N'AgHealth' AND ar.replica_server_name = N'hadrlab3';" | tr -d '\r' | xargs)
    [ "$state" = "CONNECTED SYNCHRONIZING" ] && break
    sleep 1
done
echo "hadrlab1: hadrlab3 $state in AgHealth, $(( $(date +%s) - t0 )) s after the change"
