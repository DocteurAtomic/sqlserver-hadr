#!/usr/bin/env bash
# Clip 2.5: once both directions are configured, a switch of roles is a failover and jobs
# enabled or disabled, nothing else (Learn, "Switching roles"). Gives hadrlab1 its primary
# role back: the backup job of hadrlab2 disabled, the copy and the restore of hadrlab1 run
# once more then disabled, the tail of hadrlab2 WITH NORECOVERY restored on hadrlab1 WITH
# RECOVERY; then the jobs of the first direction enabled again (backup on hadrlab1, copy and
# restore on hadrlab2), and a batch written on hadrlab1 shipped to hadrlab2. The restore job of
# hadrlab2 first fails on the log backups that hadrlab2 itself wrote to the shared folder while
# it was the primary: they are removed from its copy folder, and the restore runs again. Counts the rows
# and appends the lost rows and the duration to evidence/module_02.md. Run after 09-reverse.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
repaired=""
batches='SET NOCOUNT ON; SELECT OrderReference, COUNT(*) FROM m02_registration.Enrollment.Enrollment
         WHERE OrderReference LIKE '"'"'m02 %'"'"' AND OrderReference NOT LIKE '"'"'m02 delay%'"'"'
         GROUP BY OrderReference ORDER BY 1;'
a=$(mktemp); b=$(mktemp); trap 'rm -f "$a" "$b"' EXIT
start=$(date +%s.%N)
disable_job hadrlab2 LSBackup_m02_registration
run_job hadrlab1 LSCopy_m02_registration
run_job hadrlab1 LSRestore_m02_registration
disable_job hadrlab1 LSCopy_m02_registration
disable_job hadrlab1 LSRestore_m02_registration
sql hadrlab2 -h -1 -s '|' -Q "$batches" | LC_ALL=C sort > "$a"
sql hadrlab2 <<'SQL'
SET NOCOUNT ON;
BACKUP LOG m02_registration TO DISK = N'/var/opt/mssql/share/logship/m02_registration_tail2.trn'
    WITH INIT, NORECOVERY, COMPRESSION, CHECKSUM;
SQL
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
RESTORE LOG m02_registration FROM DISK = N'/var/opt/mssql/share/logship/m02_registration_tail2.trn'
    WITH RECOVERY, CHECKSUM;
SQL
elapsed=$(awk -v s=$start -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }')
sql hadrlab1 -h -1 -s '|' -Q "$batches" | LC_ALL=C sort > "$b"
echo
echo "batch|on hadrlab2 before its tail|on hadrlab1 after the switch"
join -t '|' -a 1 -e 0 -o 0,1.2,2.2 "$a" "$b"
lost=$(join -t '|' -a 1 -e 0 -o 1.2,2.2 "$a" "$b" | awk -F'|' '{ s += $1 - $2 } END { print s }')
echo "rows lost: $lost; switch back in $elapsed s"
echo
echo "The first direction again, by its jobs:"
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
    EXEC msdb.dbo.sp_update_job @job_name = N'LSBackup_m02_registration', @enabled = 1;"
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON;
    EXEC msdb.dbo.sp_update_job @job_name = N'LSCopy_m02_registration', @enabled = 1;
    EXEC msdb.dbo.sp_update_job @job_name = N'LSRestore_m02_registration', @enabled = 1;"
for n in hadrlab1 hadrlab2; do
    sql $n -h -1 -s '|' -Q "SET NOCOUNT ON; SELECT @@SERVERNAME, name, enabled FROM msdb.dbo.sysjobs
        WHERE name LIKE N'LS%[_]m02[_]registration' ORDER BY name;"
done
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; EXEC m02_registration.dbo.m02_register 20, 'm02 batch back';"
run_job hadrlab1 LSBackup_m02_registration
run_job hadrlab2 LSCopy_m02_registration
# The copy job of hadrlab2 has just copied, from the shared folder, the log backups that
# hadrlab2 took itself while it was the primary. Its restore job stops on the first one.
if ! run_job hadrlab2 LSRestore_m02_registration; then
    echo
    echo "hadrlab2, the error of its restore job (msdb.dbo.log_shipping_monitor_error_detail):"
    sql hadrlab2 -h -1 -s '|' <<'SQL'
SET NOCOUNT ON;
SELECT TOP 3 CONVERT(varchar(12), log_time, 114),
       LEFT(REPLACE(message, N'/var/opt/mssql/logship-copy/m02_registration', N'<copy>'), 220)
FROM msdb.dbo.log_shipping_monitor_error_detail
WHERE agent_type = 2 ORDER BY log_time DESC, sequence_number DESC;
SQL
    echo
    echo "The log backups that hadrlab2 took itself, removed from its copy folder:"
    own=$(sql hadrlab2 -h -1 <<'SQL' | tr -d '\r'
SET NOCOUNT ON;
SELECT DISTINCT REVERSE(LEFT(REVERSE(f.physical_device_name), CHARINDEX(N'/', REVERSE(f.physical_device_name)) - 1))
FROM msdb.dbo.backupset AS b
JOIN msdb.dbo.backupmediafamily AS f ON f.media_set_id = b.media_set_id
WHERE b.database_name = N'm02_registration' AND b.type = 'L' AND b.server_name = @@SERVERNAME
  AND f.physical_device_name LIKE N'/var/opt/mssql/share/logship/m02[_]registration/%';
SQL
)
    for f in $own; do
        echo "  $f"
        $engine exec hadrlab2 rm -f "/var/opt/mssql/logship-copy/m02_registration/$f"
    done
    run_job hadrlab2 LSRestore_m02_registration
    repaired=" after removing from the copy folder of hadrlab2 the $(echo $own | wc -w) log backup(s) it had taken itself"
fi
count="SET NOCOUNT ON; SELECT CONCAT(@@SERVERNAME, ': ', CAST(DATABASEPROPERTYEX(N'm02_registration', 'Status') AS nvarchar(20)),
    IIF(CAST(DATABASEPROPERTYEX(N'm02_registration', 'IsInStandBy') AS int) = 1, N' STANDBY', N''), ', ',
    COUNT(*), ' rows of m02 batch back')
    FROM m02_registration.Enrollment.Enrollment WHERE OrderReference = 'm02 batch back';"
sql hadrlab1 -h -1 -Q "$count"
sql hadrlab2 -h -1 -Q "$count"
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 2, log shipping, roles switched back from hadrlab2 to hadrlab1 by jobs only (no full backup, three containers on one host): $lost rows lost, $elapsed s; the restore job of hadrlab2 shipping again$repaired" >> evidence/module_02.md
