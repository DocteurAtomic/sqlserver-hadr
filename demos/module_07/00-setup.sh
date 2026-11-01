#!/usr/bin/env bash
# Module 7 runs on the course's Windows cluster, filmed by the trainer, not on the containers:
# its demos are PowerShell and T-SQL scripts for a node of that cluster (see README.md here),
# and its exercise reads the cluster outputs of data/cluster/. Nothing to prepare on the lab.
# Usage: ./demos/module_07/00-setup.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
[ -d data/cluster/start ] || { echo "data/cluster/start is missing: the exercise of module 7 needs it" >&2; exit 1; }
echo "Module 7 needs no change to the lab: the exercise reads data/cluster/."
