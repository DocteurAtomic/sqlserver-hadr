#!/usr/bin/env bash
# The state of the Pacemaker lab, read on both sides: the cluster (pcs status, without the
# daemons), then what SQL Server sees of the group on each node, and where a connection to
# the virtual address lands.
# Usage: ./extra/pacemaker/status.sh
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
pcs status | sed -n '/^Node List/,/^Daemon Status/p' | grep -v '^Daemon Status' | sed '/^$/d'
for n in $nodes; do
    sql $n -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'$n: ', ISNULL(rs.role_desc, N'?'), N' ',
        ISNULL(rs.synchronization_health_desc, N'?'), N', copy ', ISNULL(d.synchronization_state_desc, N'none'))
        FROM sys.availability_groups AS g
        JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.group_id = g.group_id AND rs.is_local = 1
        LEFT JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = rs.replica_id AND d.is_local = 1
        WHERE g.name = N'$ag';" 2>&1 | tail -1
done
echo "a connection to $vip from pc3 lands on: $(lands_on pc3 $vip -d $db)"
