#!/usr/bin/env bash
# ci: skip (the RESUME takes 7 to 13 minutes on the lab, see step 3)
# Clip 10.2: a resumable rebuild, paused and resumed. On hadrlab1, in m10_registration.dbo.Visit
# (1 000 000 rows):
#   1. ALTER INDEX pk_Visit REBUILD WITH (ONLINE = ON, RESUMABLE = ON), paused from another
#      session three seconds later: sys.index_resumable_operations says PAUSED, and how far it
#      went; the session of the rebuild is disconnected (Msg 1219);
#   2. while it is paused, a log backup: the log of the part already done is freed, as for any
#      other committed work (log_since_last_log_backup_mb before and after);
#   3. RESUME: the rebuild goes on from where it stopped. On the lab (SQL Server 2025 CU7),
#      the resumed rebuild runs on the processor, without waiting, for 7 to 13 minutes, where
#      the whole rebuild in one go takes 6 seconds: measured three times in the group, once
#      outside it, and slower still with MAXDOP = 1. Cause not established; the script waits
#      for it, at most 20 minutes.
# Appends the durations to evidence/module_10.md. Run after 00-setup.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
mkdir -p evidence
out=$(mktemp)
trap 'rm -f "$out"' EXIT
echo "== 1. hadrlab1: REBUILD WITH (ONLINE = ON, RESUMABLE = ON), then PAUSE"
sql hadrlab1 -d m10_registration -Q "ALTER INDEX pk_Visit ON dbo.Visit REBUILD WITH (ONLINE = ON, RESUMABLE = ON);" > "$out" 2>&1 &
r=$!
sleep 3
sql hadrlab1 -d m10_registration -Q "SET NOCOUNT ON; ALTER INDEX pk_Visit ON dbo.Visit PAUSE;
SELECT name, state_desc, CAST(percent_complete AS decimal(5,1)) AS percent_complete, page_count,
       CONVERT(varchar(8), last_pause_time, 108) AS paused_at
FROM sys.index_resumable_operations;"
wait $r || true
echo "-- the session of the rebuild:"
grep -E '^Msg|disconnected' "$out" | head -2 | sed 's/^/  /'
echo
echo "== 2. hadrlab1: BACKUP LOG while the rebuild is paused"
sql hadrlab1 -d m10_registration -Q "SET NOCOUNT ON;
SELECT CAST(log_since_last_log_backup_mb AS decimal(9,1)) AS log_mb_before FROM sys.dm_db_log_stats(DB_ID());
BACKUP LOG m10_registration TO DISK = N'/var/opt/mssql/share/m10/m10_registration-paused.trn' WITH INIT;
SELECT CAST(log_since_last_log_backup_mb AS decimal(9,1)) AS log_mb_after FROM sys.dm_db_log_stats(DB_ID());" | grep -v '^Processed'
echo
echo "== 3. hadrlab1: RESUME"
timeout 1200 bash -c ". setup/lib.sh; sql hadrlab1 -d m10_registration -Q \"SET NOCOUNT ON; DECLARE @t datetime2 = SYSDATETIME();
ALTER INDEX pk_Visit ON dbo.Visit RESUME;
SELECT DATEDIFF(millisecond, @t, SYSDATETIME()) AS resume_ms,
       (SELECT COUNT(*) FROM sys.index_resumable_operations) AS operations_left;\"" | tee "$out"
ms=$(awk 'NR == 3 { print $1 }' "$out")
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 10, resumable rebuild of pk_Visit (1 000 000 rows) paused after 3 s, resumed in $ms ms; three containers on one host" >> evidence/module_10.md
