#!/usr/bin/env bash
# Clip 10.2: an online rebuild that blocks all the same, then WAIT_AT_LOW_PRIORITY. On hadrlab1,
# in m10_registration.dbo.Contact (200 000 rows), twice:
#   A: BEGIN TRAN, UPDATE of the row 1, kept open 20 seconds, then COMMIT (a forgotten
#      transaction);
#   B, one second later: ALTER INDEX pk_Contact REBUILD WITH (ONLINE = ON), first plain, then
#      with WAIT_AT_LOW_PRIORITY (MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = SELF);
#   C, one second after B: 20 sessions, each updating its own row, none locked by A; each
#      prints how long it waited.
# Between C and the end of A, the locks on the table as sys.dm_tran_locks shows them, partition
# by partition: the instance sees 22 processors, so SQL Server partitions the table locks
# (lock partitioning, from 16 processors), and whether a session of C waits depends on the
# partition it lands on. A is opened again, at most ten times, until its lock lands on a
# partition of 8 or more: on partition 0, nobody would wait, and the scene would show nothing.
# Appends the waits of C to evidence/module_10.md. Run after 00-setup.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p evidence
partition_of_a() {  # the session tagged m10_A (sqlcmd -H) and the partition of its IX lock, once it holds it
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(l.request_session_id, ' ', l.resource_lock_partition)
FROM sys.dm_tran_locks AS l JOIN sys.dm_exec_sessions AS s ON s.session_id = l.request_session_id
WHERE s.host_name = N'm10_A' AND l.resource_database_id = DB_ID(N'm10_registration')
  AND l.resource_type = N'OBJECT' AND l.request_mode = N'IX';" | tr -d '\r' | grep -v '^ *$' || true
}
scene() {  # $1: label, $2: the WITH clause of the rebuild
    echo "== $1"
    local p=-1 try
    for try in $(seq 1 10); do
        sql hadrlab1 -d m10_registration -H m10_A -h -1 -Q "SET NOCOUNT ON; BEGIN TRAN;
UPDATE dbo.Contact SET last_name = last_name WHERE id = 1;
PRINT CONCAT('A, session ', @@SPID, ': row 1 updated, transaction left open 20 s');
WAITFOR DELAY '00:00:20'; COMMIT; PRINT 'A: COMMIT';" > "$tmp/a" 2>&1 &
        a=$!
        r=""
        for i in $(seq 1 25); do r=$(partition_of_a); [ -n "$r" ] && break; sleep 0.2; done
        [ -n "$r" ] || { echo "A holds no lock on dbo.Contact after 5 s" >&2; exit 1; }
        spid=${r% *}; p=${r#* }
        [ "$p" -ge 8 ] && break
        sql hadrlab1 -Q "KILL $spid;" >/dev/null 2>&1 || true
        wait $a || true
    done
    echo "A holds its IX lock on partition $p of the table (try $try)"
    sql hadrlab1 -d m10_registration -h -1 -Q "SET NOCOUNT ON; DECLARE @t datetime2 = SYSDATETIME();
PRINT CONCAT('B, session ', @@SPID, ': ALTER INDEX pk_Contact ON dbo.Contact REBUILD $2');
ALTER INDEX pk_Contact ON dbo.Contact REBUILD $2;
PRINT CONCAT('B: rebuild finished after ', DATEDIFF(millisecond, @t, SYSDATETIME()), ' ms');" > "$tmp/b" 2>&1 &
    b=$!; sleep 1
    pids=""
    for i in $(seq 1 20); do
        sql hadrlab1 -d m10_registration -h -1 -Q "SET NOCOUNT ON; DECLARE @t datetime2 = SYSDATETIME();
UPDATE dbo.Contact SET last_name = last_name WHERE id = $(( i + 1 ));
DECLARE @ms int = DATEDIFF(millisecond, @t, SYSDATETIME());
PRINT CONCAT('C ', @ms);" > "$tmp/c$i" 2>&1 &
        pids="$pids $!"
    done
    sleep 3
    echo "-- 3 s after C, the locks on dbo.Contact, other than the S locks granted to B:"
    sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT l.request_session_id AS session, l.request_mode AS mode, l.request_status AS status,
       l.resource_lock_partition AS partition
FROM sys.dm_tran_locks AS l
WHERE l.resource_database_id = DB_ID(N'm10_registration') AND l.resource_type = N'OBJECT'
  AND l.resource_associated_entity_id = OBJECT_ID(N'm10_registration.dbo.Contact')
  AND l.resource_subtype = N'' AND NOT (l.request_mode = N'S' AND l.request_status = N'GRANT')
ORDER BY l.resource_lock_partition, l.request_status, l.request_session_id;
SELECT COUNT(*) AS partitions_where_B_holds_S FROM sys.dm_tran_locks
WHERE resource_database_id = DB_ID(N'm10_registration') AND resource_type = N'OBJECT'
  AND request_mode = N'S' AND request_status = N'GRANT' AND resource_subtype = N'';"
    wait $a $b $pids || true
    grep -v '^ *$' "$tmp/a" "$tmp/b" | sed 's/^[^:]*://'
    cat "$tmp"/c* | awk '$1 == "C" && $2 + 0 > 1000 { w++; if ($2 + 0 > max) max = $2 + 0 } END {
        printf "C: %d sessions out of 20 waited more than a second (longest %.1f s)\n", w, max / 1000 }' | tee "$tmp/sum"
    echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 10, $1, A on partition $p: $(sed 's/^C: //' "$tmp/sum"), transaction left open 20 s; three containers on one host, 22 processors seen" >> evidence/module_10.md
    echo
}
scene "online rebuild" "WITH (ONLINE = ON)"
scene "online rebuild at low priority" "WITH (ONLINE = ON (WAIT_AT_LOW_PRIORITY (MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = SELF)))"
