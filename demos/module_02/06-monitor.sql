-- instance: hadrlab2
-- Clip 2.3: what the secondary knows of its log shipping, and what the alerts watch. Without
-- a monitor server, each instance keeps its own part: the backup on the primary, the copy and
-- the restore on the secondary. Run after 03-ship-by-hand.sh. Changes nothing.
USE master;
SET NOCOUNT ON;
GO
-- 1. The summary that the alert job reads: status 0 is fine, 1 is an alert.
EXEC master.dbo.sp_help_log_shipping_monitor;
GO
-- 2. The thresholds, and whether an alert is raised at all: the defaults of
--    sp_add_log_shipping_secondary_database, since 02-secondary.sql gives none.
SELECT secondary_database, restore_threshold, threshold_alert, threshold_alert_enabled,
       last_copied_file, last_restored_file, last_restored_latency
FROM msdb.dbo.log_shipping_monitor_secondary;
GO
-- 3. The alert job of the instance, and the error it raises when a threshold is passed.
SELECT j.name AS job, j.enabled, sc.freq_subday_interval AS every_n_minutes, s.command
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobsteps AS s ON s.job_id = j.job_id
JOIN msdb.dbo.sysjobschedules AS js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules AS sc ON sc.schedule_id = js.schedule_id
WHERE j.name LIKE N'LSAlert[_]%';
SELECT message_id, severity, is_event_logged, LEFT(text, 120) AS text
FROM sys.messages WHERE message_id IN (14420, 14421) AND language_id = 1033;
GO
