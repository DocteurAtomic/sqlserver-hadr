#!/usr/bin/env bash
# Clip 13.3: SQL Server stopped on the primary, the node still alive (systemctl stop
# mssql-server on pc1), the client on pc3 writing through the virtual address. Measured: when
# pc2 becomes PRIMARY, the first row on pc2, the rows lost, what pcs says of pc1 (the agent
# does not start SQL Server again); then SQL Server started by hand on pc1, which comes back as
# a secondary in SQL Server; how long until Pacemaker runs the resource on pc1 again (the
# failed start is forgotten after failure-timeout, 30 s, at the next recheck of the cluster,
# 2 min at most; pcs resource cleanup forgets it at once); and pc1 made primary again.
# Run after all.sh, pc1 primary. Leaves pc1 primary.
set -uo pipefail
cd "$(dirname "$0")/.."
. ./lib.sh
. demos/wait.sh
out=$(mktemp); trap 'rm -f "$out"' EXIT
label=stopped-$(date -u +%H%M%S)
./writer.sh 90 $label > "$out" &
w=$!
sleep 4
echo "== pc1: systemctl stop mssql-server ($(date -u +%T.%3N) UTC)"
podman exec pc1 systemctl stop mssql-server
echo "  SQL Server stopped on pc1 at $(date -u +%T.%3N) UTC"
until_true 120 "pc2 PRIMARY in its DMV" role_is pc2 PRIMARY
until_true 60 "the virtual address on pc2" vip_on pc2
wait $w
echo "  the client on pc3:"
summary "$out"
outage "$out" pc1 pc2
echo "  rows the client got committed: $(grep -c -E ' pc[12]$' "$out"); rows on the primary, $(promoted): $(sql $(promoted) -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM $db.dbo.Registration WHERE email = '$label@pachadata.example'" | tr -d ' \r')"
echo "  pcs status, the resources and the failed actions:"
pcs status | sed -n '/Clone Set/,/^Daemon Status/p' | grep -v -e '^Daemon Status' -e '^  \* Last' | sed '/^$/d' | cut -c1-140 | sed 's/^/    /'
echo "  pc1: mssql-server $(podman exec pc1 systemctl is-active mssql-server)"
echo
echo "== pc1: systemctl start mssql-server ($(date -u +%T.%3N) UTC)"
podman exec pc1 systemctl start mssql-server
until_true 120 "pc1 SECONDARY in its DMV" role_is pc1 SECONDARY
until_true 120 "pc1: its copy SYNCHRONIZED" copy_is pc1 SYNCHRONIZED
pc1_back() { pcs status resources 2>/dev/null | grep -E 'Unpromoted' | grep -q pc1; }
until_true 180 "pcs lists pc1 Unpromoted again, without cleanup" pc1_back || {
    echo "  pcs resource cleanup ag_cluster"; pcs resource cleanup ag_cluster >/dev/null 2>&1
    until_true 60 "pcs lists pc1 Unpromoted again, after the cleanup" pc1_back; }
echo
echo "== pcs resource move ag_cluster-clone pc1 --promoted"
settle
pcs resource move ag_cluster-clone pc1 --promoted 2>&1 | tail -1 | sed 's/^/  /'
./status.sh
