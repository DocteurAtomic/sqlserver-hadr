#!/usr/bin/env bash
# Clip 4.1: what a commit waits for. On hadrlab1, the same batch of 2,000 single-row INSERT
# statements, each one its own transaction (autocommit), in a loop on the server, three
# times in each of two databases: m04_registration, in AgPacha with hadrlab2 in synchronous
# commit, then m04_solo, outside any group, on the same instance. Then the same 2,000 rows
# in a single transaction, in m04_registration. For each run: the duration, and the waits of
# the session (sys.dm_exec_session_wait_stats, read before and after): HADR_SYNC_COMMIT, the
# wait for the synchronous secondary, its count and its time, and WRITELOG, the wait for the
# local log. Appends the averages to evidence/module_04.md. Run after 00-setup.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
runs=$(mktemp)
trap 'rm -f "$runs"' EXIT
batch() {  # database, label, 1 for a single transaction
    sql hadrlab1 -h -1 -s '|' -v DB="$1" LABEL="$2" ONE="$3" <<'SQL'
SET NOCOUNT ON;
DECLARE @s0 bigint, @c0 bigint, @l0 bigint, @t0 datetime2(3), @i int = 0;
SELECT @s0 = ISNULL(SUM(IIF(wait_type = N'HADR_SYNC_COMMIT', wait_time_ms, 0)), 0),
       @c0 = ISNULL(SUM(IIF(wait_type = N'HADR_SYNC_COMMIT', waiting_tasks_count, 0)), 0),
       @l0 = ISNULL(SUM(IIF(wait_type = N'WRITELOG', wait_time_ms, 0)), 0)
FROM sys.dm_exec_session_wait_stats WHERE session_id = @@SPID;
SET @t0 = SYSDATETIME();
IF $(ONE) = 1 BEGIN TRANSACTION;
WHILE @i < 2000
BEGIN
    INSERT [$(DB)].dbo.Registration (email) VALUES (CONCAT('commit', @i, '@pachadata.example'));
    SET @i += 1;
END;
IF $(ONE) = 1 COMMIT;
DECLARE @ms int = DATEDIFF(millisecond, @t0, SYSDATETIME());
SELECT N'$(LABEL)', N'$(DB)', @ms,
       ISNULL(SUM(IIF(wait_type = N'HADR_SYNC_COMMIT', waiting_tasks_count, 0)), 0) - @c0,
       ISNULL(SUM(IIF(wait_type = N'HADR_SYNC_COMMIT', wait_time_ms, 0)), 0) - @s0,
       ISNULL(SUM(IIF(wait_type = N'WRITELOG', wait_time_ms, 0)), 0) - @l0
FROM sys.dm_exec_session_wait_stats WHERE session_id = @@SPID;
SQL
}
echo "hadrlab1, the replicas of AgPacha for m04_registration:"
sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, ar.availability_mode_desc AS mode,
       d.synchronization_state_desc AS sync, d.is_commit_participant AS commit_participant
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
WHERE d.database_id = DB_ID(N'm04_registration') ORDER BY ar.replica_server_name;"
echo
echo "2,000 transactions of one row each, then 2,000 rows in one transaction:"
echo "run|database|duration_ms|hadr_sync_commit_waits|hadr_sync_commit_ms|writelog_ms"
for i in 1 2 3; do batch m04_registration "in AgPacha, autocommit, run $i" 0 | tee -a "$runs"; done
for i in 1 2 3; do batch m04_solo "outside any group, autocommit, run $i" 0 | tee -a "$runs"; done
for i in 1 2 3; do batch m04_registration "in AgPacha, one transaction, run $i" 1 | tee -a "$runs"; done
echo
echo "Averages of the three runs:"
awk -F'|' '{ k = $1; sub(/, run [0-9]+$/, "", k); n[k]++; d[k] += $3; w[k] += $4; s[k] += $5; o[k] = o[k] ? o[k] : NR }
     END { for (k in n) printf "%d|%s|%.0f ms|%.0f waits|%.0f ms of HADR_SYNC_COMMIT|%.2f ms per wait\n",
           o[k], k, d[k] / n[k], w[k] / n[k], s[k] / n[k], (w[k] ? s[k] / w[k] : 0) }' "$runs" \
    | sort -n | cut -d'|' -f2-
line=$(awk -F'|' '{ k = $1; sub(/, run [0-9]+$/, "", k); n[k]++; d[k] += $3; w[k] += $4; s[k] += $5; o[k] = o[k] ? o[k] : NR }
     END { for (k in n) printf "%d|%s %.0f ms (%.0f HADR_SYNC_COMMIT waits, %.0f ms)\n", o[k], k, d[k] / n[k], w[k] / n[k], s[k] / n[k] }' "$runs" \
    | sort -n | cut -d'|' -f2 | paste -sd ';' | sed 's/;/; /g')
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 4, 2,000 single-row INSERT statements on hadrlab1, average of three runs, hadrlab2 in synchronous commit, three containers on one host: $line" >> evidence/module_04.md
