#!/usr/bin/env bash
# A solution of the exercise of module 13: a planned failover to pc2 asked to the cluster, a
# row written there through the virtual address, then the way back to pc1. With pcs 0.11
# (Ubuntu 24.04), "pcs resource move" removes by itself the location constraint it creates;
# "pcs resource clear" then has nothing to do, and is kept for older pcs and for
# "pcs resource move-with-constraint".
set -euo pipefail
cd "$(dirname "$0")/../.."
. ./lib.sh
pcs resource move ag_cluster-clone pc2 --promoted
pcs resource clear ag_cluster-clone
# The client gets through as soon as the virtual address has moved: try for a minute.
for i in $(seq 1 30); do
    podman exec -i pc3 /opt/mssql-tools18/bin/sqlcmd -C -l 2 -S $vip -U sa -d ex_pcs -b -h -1 -W \
        -Q "SET NOCOUNT ON; INSERT dbo.Visit OUTPUT inserted.server DEFAULT VALUES;" 2>/dev/null && break
    sleep 2
done
pcs resource move ag_cluster-clone pc1 --promoted
pcs resource clear ag_cluster-clone
pcs constraint location --full
