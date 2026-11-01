#!/usr/bin/env bash
# Clip 13.2: the node of the primary lost at once (podman kill pc1, the container killed with
# its SQL Server, Corosync and Pacemaker), while the client on pc3 writes every half second
# through the virtual address. Measured: when pcs on pc2 sees pc1 offline, when pc2 becomes
# PRIMARY and holds the virtual address, the first row committed on pc2, the rows lost; then
# pc1 started again: it comes back as a secondary, when its copy is SYNCHRONIZED. Finally pc1
# is made primary again by pcs resource move.
# Run after all.sh, pc1 primary. Leaves pc1 primary.
set -uo pipefail
cd "$(dirname "$0")/.."
. ./lib.sh
. demos/wait.sh
out=$(mktemp); trap 'rm -f "$out"' EXIT
label=killed-$(date -u +%H%M%S)
./writer.sh 80 $label > "$out" &
w=$!
sleep 4
echo "== podman kill pc1 ($(date -u +%T.%3N) UTC)"
podman kill pc1 >/dev/null
until_true 60 "pcs on pc2 sees pc1 OFFLINE" pcs_offline pc1 pc2
until_true 90 "pc2 PRIMARY in its DMV" role_is pc2 PRIMARY
until_true 60 "the virtual address on pc2" vip_on pc2
wait $w
echo "  the client on pc3:"
summary "$out"
outage "$out" pc1 pc2
echo "  rows the client got committed: $(grep -c -E ' pc[12]$' "$out"); rows on pc2: $(sql pc2 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM $db.dbo.Registration WHERE email = '$label@pachadata.example'" | tr -d ' \r')"
echo
echo "== podman start pc1 ($(date -u +%T.%3N) UTC)"
podman start pc1 >/dev/null
until_true 120 "pc1 SECONDARY in its DMV" role_is pc1 SECONDARY
until_true 120 "pc1: its copy SYNCHRONIZED" copy_is pc1 SYNCHRONIZED
until_true 120 "pcs lists pc1 online" pcs_online pc1
echo
echo "== pcs resource move ag_cluster-clone pc1 --promoted"
settle
pcs resource move ag_cluster-clone pc1 --promoted 2>&1 | tail -1 | sed 's/^/  /'
./status.sh
