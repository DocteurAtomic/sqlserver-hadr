#!/usr/bin/env bash
# Clip 13.1: the group AgPcs under Pacemaker, read from both sides.
#   1. the cluster: nodes, resources and constraints (pcs);
#   2. the resource agent: the package mssql-server-ha and the agents it installs;
#   3. what SQL Server sees: the cluster type, the failover mode, the value of
#      REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT set by the agent, the cluster DMVs;
#      then the same value set to 1 by hand, and how long the agent takes to set it back;
#   4. a failover asked in T-SQL on the secondary (refused, Msg 47104);
#   5. a connection to the virtual address, and to the name of the listener.
# Run after all.sh, pc1 primary. Changes nothing.
set -uo pipefail
cd "$(dirname "$0")/.."
. ./lib.sh
echo "== 1. pc1: pcs status"
pcs status | sed -n '/^Cluster Summary/,/^Daemon Status/p' | grep -v -e '^Daemon Status' -e 'Last updated' -e 'Last change' | sed '/^$/d'
echo
echo "== pc1: pcs resource config ag_cluster-clone (attributes) and pcs constraint"
pcs resource config ag_cluster-clone | grep -E 'Clone:|notify|promotable|Resource:|ag_name|failure-timeout|monitor-interval-1[12]'
pcs constraint | sed '/^$/d'
echo
echo "== 2. pc1: the resource agents of mssql-server-ha"
podman exec pc1 dpkg-query -W -f='${Package} ${Version}\n' mssql-server mssql-server-ha pacemaker corosync pcs
podman exec pc1 ls /usr/lib/ocf/resource.d/mssql
echo
echo "== 3. pc1: what SQL Server sees of the group"
sql pc1 -s '|' <<'SQL'
SET NOCOUNT ON;
SELECT name, cluster_type_desc, required_synchronized_secondaries_to_commit AS required_sync FROM sys.availability_groups;
SELECT replica_server_name, availability_mode_desc, failover_mode_desc FROM sys.availability_replicas;
SELECT ISNULL(NULLIF(cluster_name, N''), N'(empty)') AS cluster_name, quorum_type_desc, quorum_state_desc FROM sys.dm_hadr_cluster;
SELECT member_name, member_type_desc, member_state_desc FROM sys.dm_hadr_cluster_members;
SQL
echo
echo "== pc1: REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT set to 1 by hand ($(date -u +%T.%3N) UTC)"
sql pc1 -Q "ALTER AVAILABILITY GROUP $ag SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1);"
t0=$(date +%s.%N)
for i in $(seq 1 120); do
    v=$(sql pc1 -h -1 -Q "SET NOCOUNT ON; SELECT required_synchronized_secondaries_to_commit FROM sys.availability_groups WHERE name = N'$ag'" | tr -d ' \r')
    [ "$v" = 0 ] && break
    sleep 0.5
done
echo "  back to $v after $(echo "$(date +%s.%N) - $t0" | bc | cut -c1-4) s (read every half second)"
echo
echo "== 4. pc2: ALTER AVAILABILITY GROUP AgPcs FAILOVER"
sql pc2 -Q "ALTER AVAILABILITY GROUP AgPcs FAILOVER;" 2>&1
echo
echo "== 5. pc3: where a connection lands"
echo "  by the virtual address $vip: $(lands_on pc3 $vip -d $db)"
echo "  by the name of the listener, agpcs: $(lands_on pc3 agpcs -d $db)"
