#!/usr/bin/env bash
# Exercise of module 13: checks that AgPcs went to pc2 and came back, read in the state of the
# cluster and of the instances, never in the commands:
#   - the database ex_pcs has a row of Visit committed on pc2 (written while pc2 was primary);
#   - pcs: ag_cluster-clone promoted on pc1 again, and no location constraint left by a move
#     (cli-prefer or cli-ban), which would pin the group or ban a node;
#   - SQL Server: pc1 PRIMARY of AgPcs, the copy of ex_pcs on pc2 SYNCHRONIZED;
#   - the virtual address answers, and lands on pc1.
# Exits with 0 when everything holds, with 1 otherwise, saying what is missing.
# Usage: ./extra/pacemaker/exercise/check.sh
set -uo pipefail
cd "$(dirname "$0")/.."
. ./lib.sh
fail=0
ok() { echo "ok   $*"; }
ko() { echo "FAIL $*"; fail=1; }
q() { sql "$1" -h -1 -l 3 -Q "SET NOCOUNT ON; $2" 2>/dev/null | tr -d '\r' | sed 's/ *$//' | grep -v '^$'; }
if [ "$(q pc1 "SELECT ISNULL(DB_ID(N'ex_pcs'), 0)")" = 0 ] || [ -z "$(q pc1 "SELECT DB_ID(N'ex_pcs')")" ]; then
    echo "FAIL pc1: no database ex_pcs (run extra/pacemaker/exercise/1-start.sh first)"; exit 1
fi
on_pc2=$(q pc1 "SELECT COUNT(*) FROM ex_pcs.dbo.Visit WHERE server = N'pc2'")
[ "${on_pc2:-0}" -gt 0 ] 2>/dev/null && ok "ex_pcs: $on_pc2 row(s) committed on pc2" \
    || ko "ex_pcs: no row committed on pc2 (${on_pc2:-no answer}): the group has not been on pc2, or nothing was written there"
p=$(promoted)
[ "$p" = pc1 ] && ok "pcs: ag_cluster-clone promoted on pc1" || ko "pcs: ag_cluster-clone promoted on '${p:-none}', pc1 expected"
left=$(pcs constraint location --full 2>/dev/null | grep -o 'cli-[a-z]*-ag_cluster[-a-z]*' | sort -u | tr '\n' ' ')
[ -z "$left" ] && ok "pcs: no location constraint left by a move" \
    || ko "pcs: constraint(s) left by a move: $left(pcs resource clear ag_cluster-clone)"
role=$(q pc1 "SELECT role_desc FROM sys.dm_hadr_availability_replica_states WHERE is_local = 1")
[ "$role" = PRIMARY ] && ok "pc1: PRIMARY of AgPcs" || ko "pc1: ${role:-no answer}, PRIMARY expected"
copy=$(q pc1 "SELECT d.synchronization_state_desc FROM sys.dm_hadr_database_replica_states AS d
    JOIN sys.availability_replicas AS r ON r.replica_id = d.replica_id
    WHERE r.replica_server_name = N'pc2' AND d.database_id = DB_ID(N'ex_pcs')")
[ "$copy" = SYNCHRONIZED ] && ok "pc2: the copy of ex_pcs SYNCHRONIZED" || ko "pc2: the copy of ex_pcs ${copy:-unknown}, SYNCHRONIZED expected"
lands=$(lands_on pc3 $vip -d ex_pcs)
[ "${lands%% *}" = pc1 ] && ok "$vip: lands on pc1" || ko "$vip: '$lands', pc1 expected"
if [ $fail = 1 ]; then echo "Not there yet."; exit 1; fi
echo "AgPcs went to pc2 and came back: pc1 primary, no constraint left, ex_pcs synchronized."
