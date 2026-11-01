#!/usr/bin/env bash
# Solution of the exercise of module 7: writes the answers, then appends to
# evidence/module_07.md the measures that the last module of the course reuses. Each number is
# computed from data/cluster/ (events.txt for the actions, the cluster and error logs for what
# the nodes did), never typed. The error logs are in the servers' local time, UTC minus 8 hours.
# Usage: ./exercises/module_07/solution/2-solution.sh
set -euo pipefail
cd "$(dirname "$0")/../../.."
d=data/cluster
cat > exercises/module_07/answers.txt <<'ANSWERS'
# Solution. SQL02 holds the only vote at the start: dynamic quorum has zeroed the vote of
# SQL01, since two nodes without a witness would make an even count.
votes=1
voters=SQL02
# SQL01 has no vote: SQL02 keeps 1 vote out of 1.
sql01_power_loss=kept
# SQL02 takes the only vote with it: SQL01 is left with 0 out of 1.
sql02_power_loss=lost
# A clean shutdown gives the vote to SQL01 before SQL02 leaves.
sql02_shutdown=kept
# With the witness, three votes: SQL01 and the witness keep 2 out of 3.
sql02_power_loss_with_witness=kept
lost_quorum_at=10:54:14
ANSWERS
echo "exercises/module_07/answers.txt written."
utc() { date -u -d "2026-11-01 $1" +%s.%N; }                  # HH:MM:SS.f, UTC
local_to_utc() { date -u -d "2026-11-01 $1 -0800" +%s.%N; }    # HH:MM:SS.f, server time
event() { awk -v e="$1" '$2 " " $3 == e { print $1; exit }' "$d/events.txt"; }  # the first one
log_time() { sed -n "s/^2026\/11\/01-\([0-9:.]*\) .*$2.*/\1/p" "$1" | head -1; }
err_time() { sed -n "s/^2026-11-01 \([0-9:.]*\)|.*$2.*/\1/p" "$1" | head -1; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }
off2=$(utc "$(event 'power-off SQL02')")
lost=$(utc "$(log_time $d/sql02-power-loss/cluster-log-SQL01.txt 'Lost quorum')")
resolving=$(local_to_utc "$(err_time $d/sql02-power-loss/errorlog-SQL01.txt "from 'PRIMARY_NORMAL' to 'RESOLVING_NORMAL'")")
back=$(local_to_utc "$(err_time $d/sql02-power-loss/errorlog-SQL01.txt "from 'PRIMARY_PENDING' to 'PRIMARY_NORMAL'")")
on2=$(utc "$(event 'power-on SQL02')")
off1=$(utc "$(event 'power-off SQL01')")
primary2=$(local_to_utc "$(err_time $d/sql01-power-loss/errorlog-SQL02.txt "from 'PRIMARY_PENDING' to 'PRIMARY_NORMAL'")")
votes() {  # DynamicWeight of the Up nodes, plus the witness vote when there is a witness
    local n w=0
    n=$(awk '$1 ~ /^[0-9]+$/ && $3 == "Up" { s += $5 } END { print s + 0 }' "$d/$1/nodes.txt")
    if [ -n "$(sed -n 's/^QuorumResource *: *//p' "$d/$1/quorum.txt" | tr -d ' ')" ]; then
        w=$(sed -n 's/^WitnessDynamicWeight *: *//p' "$d/$1/cluster.txt" | tr -d ' ')
    fi
    echo $((n + w))
}
mkdir -p evidence
cond="trainer's Windows cluster, two nodes (Windows Server 2019, SQL Server 2025 CU9) on one host, read from data/cluster"
{
    echo "- $(date +%F) module 7: without a witness, $(votes start) vote(s) counted for 2 nodes; with a file share witness, $(votes with-witness) ($cond)."
    echo "- $(date +%F) module 7: SQL01, primary without a vote, loses power: Pacha PRIMARY on SQL02 $(secs "$off1" "$primary2") s later ($cond)."
    echo "- $(date +%F) module 7: SQL02, secondary holding the only vote, loses power: SQL01 loses the quorum $(secs "$off2" "$lost") s later, Pacha RESOLVING for $(secs "$resolving" "$back") s, until $(secs "$on2" "$back") s after SQL02 is powered on again ($cond)."
    echo "- $(date +%F) module 7: the same power loss with the witness: quorum kept, Pacha stays PRIMARY on SQL01 ($cond)."
} >> evidence/module_07.md
tail -4 evidence/module_07.md
