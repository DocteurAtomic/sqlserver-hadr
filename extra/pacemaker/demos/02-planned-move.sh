#!/usr/bin/env bash
# Clip 13.2: a planned failover asked to the cluster, pcs resource move, from pc1 to pc2 and
# back, while a client on pc3 writes a row every half second through the virtual address.
# For each move: the time the command took, when SQL Server on the target became PRIMARY, when
# the virtual address started there, the first and last row the client committed on each side,
# the location constraints left, and the rows lost (rows the client was told committed that the
# new primary does not have: none expected).
# Run after all.sh, pc1 primary. Leaves pc1 primary.
set -uo pipefail
cd "$(dirname "$0")/.."
. ./lib.sh
out=$(mktemp); trap 'rm -f "$out" "$out.pcs"' EXIT
. demos/wait.sh
move() {  # from, to, label
    local from=$1 target=$2 label=$3 m
    : > "$out"
    ./writer.sh 70 $label > "$out" &
    local w=$!
    sleep 4
    echo "== $label: pcs resource move ag_cluster-clone $target --promoted ($(date -u +%T.%3N) UTC)"
    pcs resource move ag_cluster-clone $target --promoted > "$out.pcs" 2>&1 &
    m=$!
    until_true 90 "$target PRIMARY in its DMV" role_is $target PRIMARY
    until_true 60 "the virtual address on $target" vip_on $target
    wait $m
    echo "  pcs resource move returned at $(date -u +%T.%3N) UTC:"
    sed 's/^/    /' "$out.pcs"
    echo "  location constraints left: $(pcs constraint location --full | grep -c cli- || true)"
    wait $w
    echo "  the client on pc3, one line per answer, with the first time it appeared:"
    summary "$out"
    outage "$out" $from $target
    echo "  rows the client got committed: $(grep -c -E ' pc[12]$' "$out"); rows on $target:" \
        "$(sql $target -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM $db.dbo.Registration WHERE email = '$label@pachadata.example'" | tr -d ' \r')"
    echo
}
run=$(date -u +%H%M%S)
move pc1 pc2 to-pc2-$run
move pc2 pc1 to-pc1-$run
./status.sh
