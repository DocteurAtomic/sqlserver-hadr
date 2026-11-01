#!/usr/bin/env bash
# Clip 10.3: what the index maintenance sends to the secondaries.
#   1. The log of a rebuild. hadrlab1: a log backup, then ALTER INDEX pk_Visit ON dbo.Visit
#      REBUILD WITH (ONLINE = ON); meanwhile, every half second, the largest send queue (toward
#      hadrlab3, asynchronous) and redo queue (on hadrlab2) that hadrlab1 sees. Then the size of
#      the table and the log the rebuild wrote, all of which went to each secondary.
#   2. A readable secondary. hadrlab2 made readable (SECONDARY_ROLE ALLOW_CONNECTIONS = ALL);
#      on hadrlab2, a long read of dbo.Contact; on hadrlab1, meanwhile, ALTER INDEX pk_Contact
#      REBUILD WITH (ONLINE = ON), then a row 'control' in dbo.Registration, both timed. On
#      hadrlab2, 5 s later: the redo waits (LCK_M_SCH_M) behind the read. A row 'control late'
#      is then written on hadrlab1; 10 s later, on hadrlab2, last_redone_time has not moved
#      and that row is not there. The read is killed; the time until the row appears.
#      hadrlab2 made not readable again.
# Appends the measures to evidence/module_10.md. Run after 00-setup.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
mkdir -p evidence
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
redo() {  # the redo of m10_registration on hadrlab2, as hadrlab2 sees it
    sql hadrlab2 -Q "SET NOCOUNT ON;
SELECT redo_queue_size AS redo_queue_kb, CONVERT(varchar(12), last_hardened_time, 114) AS last_hardened,
       CONVERT(varchar(12), last_redone_time, 114) AS last_redone
FROM sys.dm_hadr_database_replica_states WHERE is_local = 1 AND database_id = DB_ID(N'm10_registration');
SELECT r.session_id AS session, LEFT(r.command, 20) AS command, r.wait_type, r.wait_time / 1000 AS wait_s,
       r.blocking_session_id AS blocked_by
FROM sys.dm_exec_requests AS r
WHERE r.database_id = DB_ID(N'm10_registration') AND r.session_id <> @@SPID
  AND (r.blocking_session_id <> 0 OR r.command IN (N'DB STARTUP', N'PARALLEL REDO TASK', N'PARALLEL REDO HELP TSK'))
  AND r.wait_type LIKE N'LCK%';"
}
echo "== 1. hadrlab1: BACKUP LOG, then REBUILD of pk_Visit, the queues every half second"
sql hadrlab1 -Q "BACKUP LOG m10_registration TO DISK = N'/var/opt/mssql/share/m10/m10_registration-before.trn' WITH INIT;" >/dev/null
sql hadrlab1 -d m10_registration -h -1 -Q "SET NOCOUNT ON; DECLARE @t datetime2 = SYSDATETIME();
ALTER INDEX pk_Visit ON dbo.Visit REBUILD WITH (ONLINE = ON);
PRINT CONCAT('rebuild ', DATEDIFF(millisecond, @t, SYSDATETIME()));" > "$tmp/rebuild" 2>&1 &
r=$!
while kill -0 $r 2>/dev/null; do
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(ar.replica_server_name, ' ', d.log_send_queue_size, ' ', d.redo_queue_size)
FROM sys.dm_hadr_database_replica_states AS d JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
WHERE d.database_id = DB_ID(N'm10_registration') AND d.is_local = 0;" >> "$tmp/queues" 2>/dev/null || true
    sleep 0.5
done
wait $r
sql hadrlab1 -d m10_registration -Q "SET NOCOUNT ON;
SELECT CAST(SUM(used_page_count) * 8 / 1024.0 AS decimal(9,1)) AS table_mb
FROM sys.dm_db_partition_stats WHERE object_id = OBJECT_ID(N'dbo.Visit');
SELECT CAST(log_since_last_log_backup_mb AS decimal(9,1)) AS log_mb_written FROM sys.dm_db_log_stats(DB_ID());"
echo "  $(grep -o 'rebuild [0-9]*' "$tmp/rebuild") ms"
awk '$1 == "hadrlab3" && $2 > s { s = $2 } $1 == "hadrlab2" && $3 > q { q = $3 } END {
    printf "  largest send queue toward hadrlab3: %d KB; largest redo queue on hadrlab2: %d KB\n", s, q }' "$tmp/queues" | tee "$tmp/q1"
wait_ag_database hadrlab1 AgPacha m10_registration 120
echo
echo "== 2. hadrlab2 readable; a long read there, a rebuild on hadrlab1"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab2' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = ALL));"
for i in $(seq 1 30); do  # until hadrlab2 accepts a read of the database
    sql hadrlab2 -d m10_registration -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.Registration;" >/dev/null 2>&1 && break
    sleep 1
done
sql hadrlab2 -d m10_registration -H m10_reader -h -1 -Q "SET NOCOUNT ON; DECLARE @t datetime2 = SYSDATETIME();
SELECT COUNT_BIG(*) FROM (SELECT TOP (${READ_ROWS:-6000}) last_name FROM dbo.Contact) AS a
INNER LOOP JOIN dbo.Contact AS b ON b.last_name = a.last_name + N'x' OPTION (MAXDOP 1);
PRINT CONCAT('read ', DATEDIFF(millisecond, @t, SYSDATETIME()));" > "$tmp/read" 2>&1 &
reader=$!
sleep 3
sql hadrlab1 -d m10_registration -h -1 -Q "SET NOCOUNT ON; DECLARE @t datetime2 = SYSDATETIME();
ALTER INDEX pk_Contact ON dbo.Contact REBUILD WITH (ONLINE = ON);
PRINT CONCAT('  hadrlab1: rebuild of pk_Contact done in ', DATEDIFF(millisecond, @t, SYSDATETIME()), ' ms');
SET @t = SYSDATETIME();
INSERT dbo.Registration (label, email) VALUES ('control', 'control@pachadata.example');
PRINT CONCAT('  hadrlab1: control row committed in ', DATEDIFF(millisecond, @t, SYSDATETIME()), ' ms');"
sleep 5
echo "-- hadrlab2, 5 s later:"
redo
sql hadrlab2 -d m10_registration -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT('  hadrlab2: rows control ', COUNT(*)) FROM dbo.Registration WHERE label = 'control';"
sql hadrlab1 -d m10_registration -h -1 -Q "SET NOCOUNT ON; DECLARE @t datetime2 = SYSDATETIME();
INSERT dbo.Registration (label, email) VALUES ('control late', 'late@pachadata.example');
PRINT CONCAT('  hadrlab1: row control late committed in ', DATEDIFF(millisecond, @t, SYSDATETIME()), ' ms');"
sleep 10
echo "-- hadrlab2, 10 s later:"
redo
sql hadrlab2 -d m10_registration -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT('  hadrlab2: rows control late ', COUNT(*)) FROM dbo.Registration WHERE label = 'control late';"
spid=$(sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; SELECT session_id FROM sys.dm_exec_sessions WHERE host_name = N'm10_reader';" | tr -d '[:space:]')
[ -n "$spid" ] || { echo "the read is no longer running on hadrlab2:" >&2; cat "$tmp/read" >&2; exit 1; }
echo "-- hadrlab2: KILL $spid (the read)"
t0=$(date +%s.%N)
sql hadrlab2 -Q "KILL $spid;"
wait $reader || true
grep -E '^Msg|^read' "$tmp/read" | head -1 | sed 's/^/  the read: /' || true
for i in $(seq 1 120); do
    n=$(sql hadrlab2 -d m10_registration -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.Registration WHERE label = 'control late';" | tr -d '[:space:]')
    [ "$n" = 1 ] && break
    sleep 0.5
done
took=$(awk -v s=$t0 -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }')
echo "  hadrlab2: row control late there $took s after the KILL"
redo
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab2' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = NO));"
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 10, online rebuild of pk_Visit: $(sed 's/^  //' "$tmp/q1"); readable hadrlab2: redo blocked behind a read until its KILL, control row there $took s after it; three containers on one host" >> evidence/module_10.md
