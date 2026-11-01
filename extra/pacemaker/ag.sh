#!/usr/bin/env bash
# Creates on pc1 the database m13_registration and the group AgPcs (CLUSTER_TYPE = EXTERNAL),
# joins pc2 (it receives the database by automatic seeding) and pc3 (configuration only), and
# waits for the copy on pc2 to be SYNCHRONIZED. The group then synchronizes, and nothing fails
# it over yet: pacemaker.sh hands it to the cluster.
# Usage: ./extra/pacemaker/ag.sh     (after endpoints.sh)
set -euo pipefail
cd "$(dirname "$0")"
. ./lib.sh
sql pc1 < sql/ag-create.sql >/dev/null
for n in pc2 pc3; do
    sql $n -Q "ALTER AVAILABILITY GROUP $ag JOIN WITH (CLUSTER_TYPE = EXTERNAL);"
done
# GRANT CREATE ANY DATABASE: the automatic seeding may create the database on pc2. No effect,
# and not needed, on a configuration-only replica.
sql pc2 -Q "ALTER AVAILABILITY GROUP $ag GRANT CREATE ANY DATABASE;"
for t in $(seq 1 60); do
    state=$(sql pc1 -h -1 -Q "SET NOCOUNT ON; SELECT d.synchronization_state_desc FROM sys.dm_hadr_database_replica_states AS d
        JOIN sys.availability_replicas AS r ON r.replica_id = d.replica_id WHERE r.replica_server_name = N'pc2'" | tr -d ' \r')
    [ "$state" = SYNCHRONIZED ] && break
    sleep 1
done
echo "$ag: $db on pc1 and pc2, pc2 ${state:-not joined} after $t s; pc3 configuration only"
[ "$state" = SYNCHRONIZED ]
