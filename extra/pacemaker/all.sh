#!/usr/bin/env bash
# Builds the whole Pacemaker lab from nothing: the image if missing, the three nodes, the
# endpoints, the group AgPcs, the cluster and its resources, then prints its state.
# Usage: ./extra/pacemaker/all.sh
set -euo pipefail
cd "$(dirname "$0")"
t0=$(date +%s)
./lab.sh
./endpoints.sh
./ag.sh
./pacemaker.sh
./status.sh
echo "Pacemaker lab ready in $(( $(date +%s) - t0 )) s."
