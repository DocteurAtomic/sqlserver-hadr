-- instance: hadrlab1
-- Clip 2.1: hadrlab1 becomes the log shipping primary of m02_registration. The backup job
-- writes its log backups to the shared volume, which stands for the network share of a
-- Windows setup; hadrlab2 is declared as its secondary. The schedule runs every minute
-- instead of the usual fifteen, so that the demos do not wait. Run after 00-setup.sh.
USE master;
SET NOCOUNT ON;
GO
DECLARE @backup_job uniqueidentifier, @primary_id uniqueidentifier, @schedule int, @rc int;
EXEC @rc = master.dbo.sp_add_log_shipping_primary_database
    @database = N'm02_registration',
    @backup_directory = N'/var/opt/mssql/share/logship/m02_registration',
    @backup_share = N'/var/opt/mssql/share/logship/m02_registration',
    @backup_job_name = N'LSBackup_m02_registration',
    @backup_retention_period = 4320,      -- minutes: the log backups are kept three days
    @backup_compression = 1,
    @backup_job_id = @backup_job OUTPUT,
    @primary_id = @primary_id OUTPUT;
IF @rc <> 0 THROW 50000, N'sp_add_log_shipping_primary_database failed', 1;
-- What the procedure created: the backup job, with no schedule.
SELECT j.name AS job, j.enabled,
       (SELECT COUNT(*) FROM msdb.dbo.sysjobschedules AS js WHERE js.job_id = j.job_id) AS schedules
FROM msdb.dbo.sysjobs AS j WHERE j.job_id = @backup_job;
EXEC msdb.dbo.sp_add_schedule @schedule_name = N'LSBackupSchedule_m02_registration',
    @freq_type = 4, @freq_interval = 1,              -- every day
    @freq_subday_type = 4, @freq_subday_interval = 1, -- every minute
    @active_start_time = 0, @schedule_id = @schedule OUTPUT;
EXEC msdb.dbo.sp_attach_schedule @job_id = @backup_job, @schedule_id = @schedule;
EXEC msdb.dbo.sp_update_job @job_id = @backup_job, @enabled = 1;
EXEC master.dbo.sp_add_log_shipping_primary_secondary
    @primary_database = N'm02_registration',
    @secondary_server = N'hadrlab2',
    @secondary_database = N'm02_registration';
GO
-- What the configuration created: the jobs of the instance and the command of their step.
SELECT j.name AS job, j.enabled, s.subsystem, s.command
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobsteps AS s ON s.job_id = j.job_id
WHERE j.name LIKE N'LS%'
ORDER BY j.name;
SELECT primary_database, backup_directory, backup_retention_period, backup_compression
FROM msdb.dbo.log_shipping_primary_databases;
SELECT secondary_server, secondary_database FROM msdb.dbo.log_shipping_primary_secondaries;
GO
