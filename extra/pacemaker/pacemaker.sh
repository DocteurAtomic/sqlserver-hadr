#!/usr/bin/env bash
# Hands the group AgPcs to a Pacemaker cluster of three nodes, with the commands of Learn
# ("Configure a Pacemaker cluster for SQL Server availability groups", Ubuntu):
#   1. on each instance, the login of the resource agent and its file of credentials;
#   2. the cluster hadrpcs, Corosync with its default transport (knet), started on all nodes;
#   3. fencing disabled (lab only: there is nothing to fence in containers), the properties of
#      Learn;
#   4. the resources: ag_cluster (agent ocf:mssql:ag, v1, of mssql-server-ha 17.0.4065.4),
#      virtualip (ocf:heartbeat:IPaddr2, the address of the listener), and their constraints;
#   5. the listener of AgPcs on the virtual address.
# Two differences with Learn, measured in these containers on 1 November 2026:
#   - the Ubuntu package starts a one-node cluster: "pcs cluster destroy --all" fails ("No
#     nodes found in corosync.conf"), each node is destroyed on its own;
#   - pcs 0.11.7 warns that "promotable notify=true" is deprecated, but its advice, "promotable
#     meta notify=true", puts notify on the base resource instead of the clone: the command of
#     Learn is kept, and the warning is expected.
# Usage: ./extra/pacemaker/pacemaker.sh     (after ag.sh)
set -euo pipefail
cd "$(dirname "$0")"
. ./lib.sh
for n in $nodes; do
    sql $n -v PW="$pacemaker_password" < sql/pacemaker-login.sql
    podman exec -e PW="$pacemaker_password" $n bash -c 'mkdir -p /var/opt/mssql/secrets &&
        printf "pacemakerLogin\n%s\n" "$PW" > /var/opt/mssql/secrets/passwd &&
        chown root:root /var/opt/mssql/secrets/passwd && chmod 400 /var/opt/mssql/secrets/passwd'
done
for n in $nodes; do podman exec $n pcs cluster destroy >/dev/null 2>&1; done
podman exec pc1 bash -c 'pcs host auth pc1 pc2 pc3 -u hacluster -p "$HACLUSTER_PASSWORD"' >/dev/null 2>&1
pcs cluster setup hadrpcs pc1 addr=10.89.50.11 pc2 addr=10.89.50.12 pc3 addr=10.89.50.13 >/dev/null 2>&1
pcs cluster start --all >/dev/null 2>&1
pcs cluster enable --all >/dev/null 2>&1
for t in $(seq 1 60); do
    pcs status 2>/dev/null | grep -q 'partition with quorum' && break
    sleep 2
done
pcs property set stonith-enabled=false          # lab only: a production cluster needs fencing
pcs property set cluster-recheck-interval=2min
pcs property set start-failure-is-fatal=true
pcs resource create ag_cluster ocf:mssql:ag ag_name=$ag meta failure-timeout=30s promotable notify=true
pcs resource create virtualip ocf:heartbeat:IPaddr2 ip=$vip cidr_netmask=24
pcs constraint colocation add virtualip with promoted ag_cluster-clone INFINITY
pcs constraint order promote ag_cluster-clone then start virtualip >/dev/null
started=no
for t in $(seq 1 90); do
    pcs status resources 2>/dev/null | grep -q 'virtualip.*Started' && { started=yes; break; }
    sleep 1
done
primary=$(promoted)
[ $started = yes ] && [ -n "$primary" ] || { echo "virtualip not started, or no promoted instance of ag_cluster-clone: see pcs status" >&2; exit 1; }
sql $primary -Q "ALTER AVAILABILITY GROUP $ag ADD LISTENER N'agpcs' (WITH IP ((N'$vip', N'255.255.255.0')), PORT = 1433);"
echo "cluster hadrpcs: $ag promoted on $primary, virtualip $vip, listener agpcs"
