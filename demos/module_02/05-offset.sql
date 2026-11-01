-- instance: hadrlab2
-- Clip 2.2: the copy and the restore start at the same second as the backup, so the copy
-- often runs before the log backup of that minute is written, and the row waits for the next
-- cycle. This moves the copy to 20 seconds past each minute and the restore to 40 seconds:
-- each job finds the file of the one before it. Run after 04-delay.sh, then run 04-delay.sh
-- again to measure the difference.
USE msdb;
SET NOCOUNT ON;
GO
EXEC msdb.dbo.sp_update_schedule @name = N'LSCopySchedule_m02_registration', @active_start_time = 20;
EXEC msdb.dbo.sp_update_schedule @name = N'LSRestoreSchedule_m02_registration', @active_start_time = 40;
GO
SELECT j.name AS job, sc.name AS schedule, sc.freq_subday_interval AS every_n_minutes,
       sc.active_start_time AS starts_at_hhmmss
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobschedules AS js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules AS sc ON sc.schedule_id = js.schedule_id
WHERE j.name LIKE N'LS%[_]m02[_]registration'
ORDER BY sc.active_start_time;
GO
