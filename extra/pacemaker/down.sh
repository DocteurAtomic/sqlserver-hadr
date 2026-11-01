#!/usr/bin/env bash
# Removes the Pacemaker lab: the three nodes, their databases, the network. Keeps the image
# (podman rmi hadr-pcs:2025 removes it). The lab of the course, hadrlab1 to hadrlab3, is not
# touched: start it again with "podman start hadrlab1 hadrlab2 hadrlab3".
# Usage: ./extra/pacemaker/down.sh
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
podman rm -f -t 0 $nodes >/dev/null 2>&1
podman network rm $net >/dev/null 2>&1
for n in $nodes; do podman container exists $n && echo "$n still exists"; done
podman network exists $net && echo "$net still exists"
echo "Pacemaker lab removed (image $image kept)."
