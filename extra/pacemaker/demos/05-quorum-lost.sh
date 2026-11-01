#!/usr/bin/env bash
# Clip 13.3: two nodes of three lost at once (podman kill pc2 pc3), the primary pc1 alone.
# Measured: when pc1 loses the quorum, what becomes of the resource, the replica and the
# database (a query on it, from pc1 itself); then the quorum forced on pc1 (pcs quorum
# expected-votes 1) and what the agent answers; then pc3 alone started again, the
# configuration-only replica: the quorum and the primary come back; then pc2. The expected
# votes go back to 3 by themselves when the nodes join ("pcs quorum expected-votes 3" is
# refused while pc1 is alone: CS_ERR_INVALID_PARAM).
# Run after all.sh, pc1 primary. Leaves pc1 primary, the three nodes online.
set -uo pipefail
cd "$(dirname "$0")/.."
. ./lib.sh
. demos/wait.sh
no_quorum() { pcs status 2>/dev/null | grep -q 'partition WITHOUT quorum'; }
quorum() { pcs status 2>/dev/null | grep -q 'partition with quorum'; }
db_answers() { sql pc1 -l 2 -Q "SELECT COUNT(*) FROM $db.dbo.Registration" >/dev/null 2>&1; }
echo "== podman kill pc2 pc3 ($(date -u +%T.%3N) UTC)"
podman kill pc2 pc3 >/dev/null
until_true 60 "pc1: partition WITHOUT quorum" no_quorum
until_true 90 "pc1 RESOLVING in its DMV" role_is pc1 RESOLVING
sleep 2
echo "  pcs status on pc1, the resources:"
pcs status | sed -n '/Clone Set/,/^Daemon Status/p' | grep -v -e '^Daemon Status' | sed '/^$/d' | cut -c1-140 | sed 's/^/    /'
echo "  pc1: a query on $db:"
sql pc1 -l 2 -Q "SELECT COUNT(*) FROM $db.dbo.Registration" 2>&1 | sed 's/^/    /'
echo "  pc1: the virtual address on eth0: $(vip_on pc1 && echo yes || echo no)"
echo
echo "== pc1: pcs quorum expected-votes 1 ($(date -u +%T.%3N) UTC)"
pcs quorum expected-votes 1
until_true 30 "pc1: partition with quorum" quorum
sleep 30
echo "  pc1 after 30 s: $(sql pc1 -h -1 -Q "SET NOCOUNT ON; SELECT role_desc FROM sys.dm_hadr_availability_replica_states WHERE is_local = 1" | tr -d '\r'), pcs promoted: $(promoted || true)"
echo "  the journal of pc1, the agent's answer:"
podman exec pc1 bash -c "journalctl --no-pager --since '-60s' | grep 'Failed action promote' | tail -1 | sed 's/.*Failed action promote: //'" | sed 's/^/    /'
echo
echo "== podman start pc3, the configuration-only replica ($(date -u +%T.%3N) UTC)"
podman start pc3 >/dev/null
until_true 120 "pc1: partition with quorum" quorum
until_true 120 "pc1 PRIMARY in its DMV" role_is pc1 PRIMARY
until_true 60 "pc1: $db answers a query" db_answers
until_true 60 "the virtual address on pc1" vip_on pc1
echo
echo "== podman start pc2 ($(date -u +%T.%3N) UTC)"
podman start pc2 >/dev/null
until_true 120 "pc2: its copy SYNCHRONIZED" copy_is pc2 SYNCHRONIZED
until_true 120 "pcs lists pc2 online" pcs_online pc2
settle
echo "  pc1: the votes, once the three nodes are back (corosync-quorumtool):"
podman exec pc1 corosync-quorumtool -s | grep -E 'Expected votes|Total votes|Quorum:' | sed 's/^/    /'
./status.sh
