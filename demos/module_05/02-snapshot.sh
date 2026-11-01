#!/usr/bin/env bash
# Clip 5.1: the isolation of a read on the secondary. On hadrlab3 (ALLOW_CONNECTIONS =
# READ_ONLY, left by 01-readable.sh), a report opens a transaction in READ COMMITTED, the
# default level, reads dbo.Enrollment with the hints TABLOCKX and HOLDLOCK, waits 15 seconds,
# reads again, then commits and reads a third time. While it waits: the script sees its
# transaction in sys.dm_tran_active_snapshot_database_transactions of hadrlab3, the only one
# there (it waits for
# it, at most 30 seconds), inserts 500 enrollments on hadrlab1 and updates
# 5,000, and reads from another session
# on hadrlab3 that the 500 rows have arrived (at most 30 seconds). The report reads the same
# count twice inside its transaction, the new one after: SQL Server runs every read of a
# secondary in snapshot isolation and ignores the locking hints. Also prints the locks of the
# report and the version store of hadrlab3, which keeps the old rows for it. Run after 01-readable.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
report=$(mktemp)
trap 'rm -f "$report"' EXIT
now() { date -u '+%H:%M:%S'; }
echo "== hadrlab3: the report starts (READ COMMITTED, TABLOCKX, HOLDLOCK), in the background"
$engine exec -i hadrlab1 /opt/mssql-tools18/bin/sqlcmd -C -l 10 -S hadrlab3 -U sa -d m05_reports -K ReadOnly -h -1 -W > "$report" 2>&1 <<'SQL' &
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRANSACTION;
SELECT CONCAT(CONVERT(char(8), SYSUTCDATETIME(), 108), N'  report, in its transaction, first read: ', COUNT(*), N' enrollments')
FROM dbo.Enrollment WITH (TABLOCKX, HOLDLOCK);
WAITFOR DELAY '00:00:15';
SELECT CONCAT(CONVERT(char(8), SYSUTCDATETIME(), 108), N'  report, in its transaction, second read: ', COUNT(*), N' enrollments')
FROM dbo.Enrollment;
COMMIT;
SELECT CONCAT(CONVERT(char(8), SYSUTCDATETIME(), 108), N'  report, after COMMIT: ', COUNT(*), N' enrollments')
FROM dbo.Enrollment;
SQL
bg=$!
started=""
for i in $(seq 1 60); do
    n=$(sql hadrlab3 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.dm_tran_active_snapshot_database_transactions;" | tr -d '[:space:]')
    [ "$n" != 0 ] && { started=1; break; }
    sleep 0.5
done
[ -n "$started" ] || { echo "the transaction of the report did not show on hadrlab3 within 30 seconds" >&2; exit 1; }
echo
echo "== hadrlab3, while the report waits: its transaction and its locks"
sql hadrlab3 -Q "SET NOCOUNT ON;
SELECT t.session_id, s.transaction_isolation_level AS isolation_level_of_session, t.is_snapshot
FROM sys.dm_tran_active_snapshot_database_transactions AS t
JOIN sys.dm_exec_sessions AS s ON s.session_id = t.session_id
SELECT l.request_session_id AS session_id, l.resource_type, l.request_mode, l.request_status
FROM sys.dm_tran_locks AS l
WHERE l.resource_database_id = DB_ID(N'm05_reports') AND l.request_session_id <> @@SPID;"
echo
echo "== hadrlab1: 500 new enrollments, and 5,000 updated"
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
INSERT m05_reports.dbo.Enrollment (id, session_id, enrolled_at, email)
SELECT 100000 + id, session_id, SYSDATETIME(), CONCAT('late', id, '@pachadata.example') FROM m05_reports.dbo.Enrollment WHERE id <= 500;
UPDATE m05_reports.dbo.Enrollment SET session_id = session_id + 1 WHERE id <= 5000;
SELECT CONCAT(CONVERT(char(8), SYSUTCDATETIME(), 108), N'  hadrlab1 after the INSERT: ', COUNT(*), N' enrollments') FROM m05_reports.dbo.Enrollment;"
want=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM m05_reports.dbo.Enrollment;" | tr -d '[:space:]')
got=""
for i in $(seq 1 30); do
    got=$($engine exec -i hadrlab1 /opt/mssql-tools18/bin/sqlcmd -C -l 10 -S hadrlab3 -U sa -d m05_reports -K ReadOnly -h -1 -W \
          -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.Enrollment;" | tr -d '[:space:]')
    [ "$got" = "$want" ] && break
    sql hadrlab1 -Q "USE m05_reports; CHECKPOINT;" >/dev/null
    sleep 1
done
[ "$got" = "$want" ] || { echo "hadrlab3 shows $got enrollments, $want expected, after 30 seconds" >&2; exit 1; }
echo "$(now)  another session on hadrlab3: $got enrollments"
sql hadrlab3 -Q "SET NOCOUNT ON; SELECT DB_NAME(database_id) AS db, reserved_space_kb AS version_store_kb
FROM sys.dm_tran_version_store_space_usage WHERE database_id = DB_ID(N'm05_reports');"
echo
echo "== hadrlab3: what the report read"
wait $bg
cat "$report"
