#!/usr/bin/env bash
# Starts the three nodes of the Pacemaker lab: pc1 and pc2 (Developer, the replicas that hold
# the data), pc3 (Express, the configuration-only replica), fixed addresses on the network
# hadr-pcs. Builds the image first when it is missing (a few minutes: it downloads Ubuntu
# packages and about 300 MB of SQL Server). Sets SQL Server up on each node (mssql-conf),
# enables HADR, limits each instance to 2 GB, gives the user hacluster its password. Does not
# create the cluster: endpoints.sh, ag.sh and pacemaker.sh do the rest (or all.sh).
# Starting it again removes the three nodes and starts them anew.
# Usage: ./extra/pacemaker/lab.sh
set -euo pipefail
cd "$(dirname "$0")"
. ./lib.sh
podman image exists $image || podman build -t $image -f Containerfile .
podman rm -f -t 0 $nodes >/dev/null 2>&1 || true
podman network exists $net || podman network create --subnet $subnet $net >/dev/null
i=11
for n in $nodes; do
    # --systemd=always: systemd is the first process, it starts SQL Server, pcsd, Corosync and
    # Pacemaker. NET_ADMIN: the IPaddr2 resource adds the virtual address to eth0. NET_RAW: it
    # then announces the address by gratuitous ARP (send_arp); without it, Podman giving no
    # NET_RAW by default, the announce fails and the clients keep the MAC address of the old
    # primary until their cache expires (34 s more on the lab, measured on 1 November 2026).
    # label=disable: on a host with SELinux (Fedora, RHEL), Podman runs a systemd container in
    # the container_init_t domain, which refuses executable memory: SQL Server dies at its
    # first start (mprotect PROT_EXEC: Permission denied, an ASSERT in drtl.cpp). The domain of
    # ordinary containers, container_t, lets SQL Server run but not systemd. The lab nodes run
    # without SELinux separation; no effect on a host without SELinux (Ubuntu, Debian).
    podman run -d --name $n --hostname $n --network $net --ip 10.89.50.$i --systemd=always \
        --security-opt label=disable --cap-add NET_ADMIN --cap-add NET_RAW \
        -e MSSQL_SA_PASSWORD="$sa_password" -e SQLCMDPASSWORD="$sa_password" \
        -e HACLUSTER_PASSWORD="$hacluster_password" \
        $image >/dev/null
    i=$((i + 1))
done
for n in $nodes; do
    [ $n = pc3 ] && edition=Express || edition=Developer
    # The settings go first, so that the setup starts SQL Server with them: a restart sent
    # while the instance is still starting is ignored, and systemd then waits 30 minutes
    # (TimeoutStopSec of the mssql-server unit) before killing it.
    podman exec $n /opt/mssql/bin/mssql-conf set hadr.hadrenabled 1 >/dev/null
    podman exec $n /opt/mssql/bin/mssql-conf set memory.memorylimitmb 2048 >/dev/null
    podman exec $n bash -c "ACCEPT_EULA=Y MSSQL_PID=$edition /opt/mssql/bin/mssql-conf -n setup accept-eula" >/dev/null
    podman exec $n bash -c 'echo "hacluster:$HACLUSTER_PASSWORD" | chpasswd'
done
for n in $nodes; do
    for t in $(seq 1 60); do
        sql $n -Q "SELECT 1" >/dev/null 2>&1 && break
        sleep 2
    done
    sql $n -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(@@SERVERNAME, N': ', CAST(SERVERPROPERTY('Edition') AS nvarchar(60)),
        N' ', CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(20)), N', HADR ', CAST(SERVERPROPERTY('IsHadrEnabled') AS int))"
done
