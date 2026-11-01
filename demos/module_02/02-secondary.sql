-- instance: hadrlab2
-- Clip 2.1: hadrlab2 becomes the log shipping secondary. It restores the full backup of
-- m02_registration WITH NORECOVERY from the shared volume, then gets a copy job (from the
-- shared volume to a folder of its own) and a restore job, both every minute, restoring in
-- STANDBY so that the copy can be read between two restores. Run after 01-primary.sql.
USE master;
SET NOCOUNT ON;
GO
-- The folder the copy job writes to, on the disk of hadrlab2 (it is not on the shared volume).
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/logship-copy/m02_registration';
RESTORE DATABASE m02_registration
    FROM DISK = N'/var/opt/mssql/share/m02_registration-full.bak'
    WITH NORECOVERY, REPLACE,
         MOVE N'PachadataTraining' TO N'/var/opt/mssql/data/m02_registration.mdf',
         MOVE N'PachadataTraining_log' TO N'/var/opt/mssql/data/m02_registration_log.ldf';
GO
DECLARE @copy_job uniqueidentifier, @restore_job uniqueidentifier, @secondary_id uniqueidentifier,
        @copy_schedule int, @restore_schedule int, @rc int;
EXEC @rc = master.dbo.sp_add_log_shipping_secondary_primary
    @primary_server = N'hadrlab1',
    @primary_database = N'm02_registration',
    @backup_source_directory = N'/var/opt/mssql/share/logship/m02_registration',
    @backup_destination_directory = N'/var/opt/mssql/logship-copy/m02_registration',
    @copy_job_name = N'LSCopy_m02_registration',
    @restore_job_name = N'LSRestore_m02_registration',
    @file_retention_period = 4320,
    @copy_job_id = @copy_job OUTPUT,
    @restore_job_id = @restore_job OUTPUT,
    @secondary_id = @secondary_id OUTPUT;
IF @rc <> 0 THROW 50000, N'sp_add_log_shipping_secondary_primary failed', 1;
EXEC msdb.dbo.sp_add_schedule @schedule_name = N'LSCopySchedule_m02_registration',
    @freq_type = 4, @freq_interval = 1, @freq_subday_type = 4, @freq_subday_interval = 1,
    @active_start_time = 0, @schedule_id = @copy_schedule OUTPUT;
EXEC msdb.dbo.sp_attach_schedule @job_id = @copy_job, @schedule_id = @copy_schedule;
EXEC msdb.dbo.sp_add_schedule @schedule_name = N'LSRestoreSchedule_m02_registration',
    @freq_type = 4, @freq_interval = 1, @freq_subday_type = 4, @freq_subday_interval = 1,
    @active_start_time = 0, @schedule_id = @restore_schedule OUTPUT;
EXEC msdb.dbo.sp_attach_schedule @job_id = @restore_job, @schedule_id = @restore_schedule;
EXEC @rc = master.dbo.sp_add_log_shipping_secondary_database
    @secondary_database = N'm02_registration',
    @primary_server = N'hadrlab1',
    @primary_database = N'm02_registration',
    @restore_mode = 1,          -- STANDBY: readable between two restores
    @disconnect_users = 1;      -- the restore job disconnects the readers
IF @rc <> 0 THROW 50000, N'sp_add_log_shipping_secondary_database failed', 1;
-- The two jobs, as the procedures left them.
SELECT name AS job, enabled FROM msdb.dbo.sysjobs WHERE job_id IN (@copy_job, @restore_job) ORDER BY name;
EXEC msdb.dbo.sp_update_job @job_id = @copy_job, @enabled = 1;
EXEC msdb.dbo.sp_update_job @job_id = @restore_job, @enabled = 1;
GO
SELECT j.name AS job, j.enabled, s.command
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobsteps AS s ON s.job_id = j.job_id
WHERE j.name LIKE N'LS%'
ORDER BY j.name;
SELECT name, state_desc AS state, is_in_standby FROM sys.databases WHERE name = N'm02_registration';
GO
