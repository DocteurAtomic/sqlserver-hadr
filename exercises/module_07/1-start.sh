#!/usr/bin/env bash
# Exercise of module 7: writes exercises/module_07/answers.txt, one empty answer per line, and
# replaces the file if it already exists. No container is needed: the exercise reads the
# outputs of the course's Windows cluster in data/cluster/.
# Usage: ./exercises/module_07/1-start.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
f=exercises/module_07/answers.txt
cat > "$f" <<'ANSWERS'
# Exercise of module 7. Write each answer after its "=", read from data/cluster/.
# Start configuration (data/cluster/start): how many votes count, and which node holds them
# (node names, comma-separated when there are several).
votes=
voters=
# For each failure, starting from the healthy cluster: kept or lost (the quorum).
# SQL01 loses power, start configuration:
sql01_power_loss=
# SQL02 loses power, start configuration:
sql02_power_loss=
# SQL02 is shut down cleanly, start configuration:
sql02_shutdown=
# SQL02 loses power, configuration of data/cluster/with-witness:
sql02_power_loss_with_witness=
# In data/cluster/sql02-power-loss/cluster-log-SQL01.txt, the time (UTC, HH:MM:SS) at which
# SQL01 lost the quorum:
lost_quorum_at=
ANSWERS
echo "$f written: one empty answer per line."
