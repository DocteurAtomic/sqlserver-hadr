#!/usr/bin/env bash
# Exercise of module 7: checks the answers of exercises/module_07/answers.txt against what the
# outputs of data/cluster/ determine. Nothing is compared with the solution: each expected
# answer is computed from the files.
# - votes: the DynamicWeight of the nodes that are Up in start/nodes.txt, plus
#   WitnessDynamicWeight (start/cluster.txt) when start/quorum.txt names a witness;
#   voters: the Up nodes whose DynamicWeight is 1.
# - A node that loses power takes its current vote with it: the cluster keeps the quorum when
#   the votes left are more than half the votes counted before the loss.
# - A node shut down cleanly gives up its vote before it leaves when DynamicQuorum is 1
#   (cluster.txt): the cluster keeps the quorum; with DynamicQuorum at 0, the power loss rule.
# - lost_quorum_at: the time of the "Lost quorum" line of sql02-power-loss/cluster-log-SQL01.txt.
# Exits with 0 when every answer holds, with 1 otherwise, saying what is missing. Needs bash,
# awk and sed only: no container, no Windows.
# Usage: ./exercises/module_07/check.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
data=data/cluster
answers=exercises/module_07/answers.txt
if [ ! -f "$answers" ]; then
    echo "FAIL $answers does not exist: run exercises/module_07/1-start.sh"
    exit 1
fi
answer() {  # the last value written after "<key>=", lower case, without spaces
    sed -n "s/^$1[[:space:]]*=//p" "$answers" | tail -1 | tr -d ' \t\r' | tr 'A-Z' 'a-z'
}
nodes() {  # name, state, DynamicWeight of each node of a configuration
    awk '$1 ~ /^[0-9]+$/ && NF >= 5 { print $2, $3, $5 }' "$data/$1/nodes.txt"
}
witness_vote() {
    if [ -n "$(sed -n 's/^QuorumResource *: *//p' "$data/$1/quorum.txt" | tr -d ' \r')" ]; then
        sed -n 's/^WitnessDynamicWeight *: *//p' "$data/$1/cluster.txt" | tr -d ' \r'
    else
        echo 0
    fi
}
votes() {
    echo $(( $(nodes "$1" | awk '$2 == "Up" { s += $3 } END { print s + 0 }') + $(witness_vote "$1") ))
}
voters() {
    nodes "$1" | awk '$2 == "Up" && $3 == 1 { print $1 }' | sort | paste -sd, - | tr 'A-Z' 'a-z'
}
power_loss() {  # configuration, node
    local total lost
    total=$(votes "$1")
    lost=$(nodes "$1" | awk -v n="$2" '$1 == n { print $3 }')
    if [ $(( (total - ${lost:-0}) * 2 )) -gt "$total" ]; then echo kept; else echo lost; fi
}
shutdown() {  # configuration, node
    if [ "$(sed -n 's/^DynamicQuorum *: *//p' "$data/$1/cluster.txt" | tr -d ' \r')" = 1 ]; then
        echo kept
    else
        power_loss "$1" "$2"
    fi
}
lost_at=$(sed -n 's/^2026\/11\/01-\([0-9:]*\)\.[0-9]* .*Lost quorum.*/\1/p' "$data/sql02-power-loss/cluster-log-SQL01.txt" | head -1)
fail=0
expect() {  # key, expected value, what the answer means
    local got
    got=$(answer "$1")
    if [ -z "$got" ]; then
        echo "FAIL $1: no answer ($3)"; fail=1
    elif [ "$got" = "$2" ]; then
        echo "ok   $1 = $got"
    else
        echo "FAIL $1 = $got: this is not what data/cluster/ says ($3)"; fail=1
    fi
}
expect votes "$(votes start)" "the votes counted in start/"
expect voters "$(voters start)" "the node or nodes that hold a vote in start/"
expect sql01_power_loss "$(power_loss start SQL01)" "kept or lost"
expect sql02_power_loss "$(power_loss start SQL02)" "kept or lost"
expect sql02_shutdown "$(shutdown start SQL02)" "kept or lost"
expect sql02_power_loss_with_witness "$(power_loss with-witness SQL02)" "kept or lost"
expect lost_quorum_at "$lost_at" "HH:MM:SS, UTC"
if [ $fail = 1 ]; then echo "Some answers are missing or do not match data/cluster/."; exit 1; fi
echo "Every answer matches what the cluster outputs show."
