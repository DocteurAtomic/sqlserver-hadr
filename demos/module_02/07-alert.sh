#!/usr/bin/env bash
# ci: skip (it waits for the alert job of the Agent, which runs every two minutes)
# Clip 2.3: a delay provoked and seen. On hadrlab2, lowers the restore threshold of
# m02_registration from 45 to 2 minutes and turns its alert on, then disables the copy job:
# the log backups go on, nothing is restored any more. Reads the monitor every ten seconds
# until the alert job raises error 14421 in the error log, at most seven minutes. Then
# enables the copy job again, runs the copy and the restore, reads the monitor once more, and
# puts the threshold back to 45 minutes, alert on. Run after 06-monitor.sql.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
monitor='SET NOCOUNT ON;
DECLARE @m TABLE (status bit, is_primary bit, server sysname, database_name sysname,
    time_since_last_backup int, last_backup_file nvarchar(500), backup_threshold int,
    is_backup_alert_enabled bit, time_since_last_copy int, last_copied_file nvarchar(500),
    time_since_last_restore int, last_restored_file nvarchar(500), last_restored_latency int,
    restore_threshold int, is_restore_alert_enabled bit);
INSERT @m EXEC master.dbo.sp_help_log_shipping_monitor;
SELECT CONCAT(CONVERT(varchar(8), SYSDATETIME(), 108), '"'"' status '"'"', status,
              '"'"', minutes since last copy '"'"', time_since_last_copy,
              '"'"', since last restore '"'"', time_since_last_restore,
              '"'"', threshold '"'"', restore_threshold, '"'"', alert '"'"', is_restore_alert_enabled)
FROM @m WHERE database_name = N'"'"'m02_registration'"'"';'
sql hadrlab2 -h -1 <<'SQL'
SET NOCOUNT ON;
EXEC master.dbo.sp_change_log_shipping_secondary_database
    @secondary_database = N'm02_registration',
    @restore_threshold = 2,
    @threshold_alert_enabled = 1;
EXEC msdb.dbo.sp_update_job @job_name = N'LSCopy_m02_registration', @enabled = 0;
SELECT CONCAT(CONVERT(varchar(8), SYSDATETIME(), 108), ' threshold 2 min, alert on, LSCopy disabled');
SQL
since=$(sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(19), GETDATE(), 120);" | tr -d '\r')
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; EXEC m02_registration.dbo.m02_register 10, 'm02 batch stalled';"
t0=$(date +%s); last=""; raised=""
while :; do
    line=$(sql hadrlab2 -h -1 -Q "$monitor" | tail -1)
    state=${line#* }
    [ "$state" != "$last" ] && echo "$line" && last=$state
    raised=$(sql hadrlab2 -h -1 -Q "SET NOCOUNT ON;
        CREATE TABLE #l (LogDate datetime, ProcessInfo nvarchar(50), Text nvarchar(max));
        INSERT #l EXEC sys.xp_readerrorlog 0, 1, N'14421';
        INSERT #l EXEC sys.xp_readerrorlog 0, 1, N'out of sync';
        SELECT TOP 2 CONCAT(CONVERT(varchar(8), LogDate, 108), ' ', LEFT(Text, 300))
        FROM #l WHERE LogDate >= '$since' ORDER BY LogDate;" | sed '/^\s*$/d')
    [ -n "$raised" ] && break
    if [ $(( $(date +%s) - t0 )) -ge 420 ]; then
        echo "no error 14421 after 420 s: is the alert job LSAlert_HADRLAB2 enabled?"; exit 1
    fi
    sleep 10
done
echo
echo "The error log of hadrlab2, after $(( $(date +%s) - t0 )) s:"
echo "$raised"
sql hadrlab2 -h -1 -s '|' <<'SQL'
SET NOCOUNT ON;
SELECT TOP 1 j.name, h.run_status, CONCAT(h.run_date, ' ', h.run_time), LEFT(h.message, 300)
FROM msdb.dbo.sysjobhistory AS h JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name LIKE N'LSAlert[_]%' AND h.step_id = 1 ORDER BY h.instance_id DESC;
SQL
echo
echo "The repair: LSCopy enabled again, then a copy and a restore."
sql hadrlab2 -Q "EXEC msdb.dbo.sp_update_job @job_name = N'LSCopy_m02_registration', @enabled = 1;"
run_job hadrlab2 LSCopy_m02_registration
run_job hadrlab2 LSRestore_m02_registration
sql hadrlab2 -h -1 -Q "$monitor" | tail -1
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(COUNT(*), ' rows of m02 batch stalled on hadrlab2')
    FROM m02_registration.Enrollment.Enrollment WHERE OrderReference = 'm02 batch stalled';"
sql hadrlab2 -Q "EXEC master.dbo.sp_change_log_shipping_secondary_database
    @secondary_database = N'm02_registration', @restore_threshold = 45, @threshold_alert_enabled = 1;"
echo "threshold back to 45 minutes, alert on"
