#!/usr/bin/env bash
# Clip 2.5: the roles reversed, without a new full backup. After 08-failover.sh, hadrlab2 is
# online and hadrlab1 is RESTORING since its tail backup WITH NORECOVERY: it is already a
# secondary, ready to receive the log of hadrlab2. Following Learn ("Change roles between
# primary and secondary log shipping servers"), hadrlab2 gets a backup job to the same
# folder of the shared volume, and hadrlab1 a copy and a restore job, nothing restored by
# hand. The old jobs stay, disabled. Then a batch written on hadrlab2 is shipped to hadrlab1
# by the three jobs run in order. Run after 08-failover.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
echo "1. hadrlab2, primary:"
sql hadrlab2 <<'SQL'
USE master;
SET NOCOUNT ON;
DECLARE @backup_job uniqueidentifier, @primary_id uniqueidentifier, @schedule int, @rc int;
EXEC @rc = master.dbo.sp_add_log_shipping_primary_database
    @database = N'm02_registration',
    @backup_directory = N'/var/opt/mssql/share/logship/m02_registration',
    @backup_share = N'/var/opt/mssql/share/logship/m02_registration',
    @backup_job_name = N'LSBackup_m02_registration',
    @backup_retention_period = 4320, @backup_compression = 1,
    @backup_job_id = @backup_job OUTPUT, @primary_id = @primary_id OUTPUT;
IF @rc <> 0 THROW 50000, N'sp_add_log_shipping_primary_database failed', 1;
EXEC msdb.dbo.sp_add_schedule @schedule_name = N'LSBackupSchedule_m02_registration',
    @freq_type = 4, @freq_interval = 1, @freq_subday_type = 4, @freq_subday_interval = 1,
    @active_start_time = 0, @schedule_id = @schedule OUTPUT;
EXEC msdb.dbo.sp_attach_schedule @job_id = @backup_job, @schedule_id = @schedule;
EXEC msdb.dbo.sp_update_job @job_id = @backup_job, @enabled = 1;
EXEC master.dbo.sp_add_log_shipping_primary_secondary
    @primary_database = N'm02_registration', @secondary_server = N'hadrlab1',
    @secondary_database = N'm02_registration';
GO
SELECT name AS job, enabled FROM msdb.dbo.sysjobs WHERE name LIKE N'LS%' ORDER BY name;
GO
SQL
echo
echo "2. hadrlab1, secondary, from the database left RESTORING by the tail backup:"
sql hadrlab1 <<'SQL'
USE master;
SET NOCOUNT ON;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/logship-copy/m02_registration';
DECLARE @copy_job uniqueidentifier, @restore_job uniqueidentifier, @secondary_id uniqueidentifier,
        @s1 int, @s2 int, @rc int;
EXEC @rc = master.dbo.sp_add_log_shipping_secondary_primary
    @primary_server = N'hadrlab2', @primary_database = N'm02_registration',
    @backup_source_directory = N'/var/opt/mssql/share/logship/m02_registration',
    @backup_destination_directory = N'/var/opt/mssql/logship-copy/m02_registration',
    @copy_job_name = N'LSCopy_m02_registration', @restore_job_name = N'LSRestore_m02_registration',
    @file_retention_period = 4320,
    @copy_job_id = @copy_job OUTPUT, @restore_job_id = @restore_job OUTPUT,
    @secondary_id = @secondary_id OUTPUT;
IF @rc <> 0 THROW 50000, N'sp_add_log_shipping_secondary_primary failed', 1;
EXEC msdb.dbo.sp_add_schedule @schedule_name = N'LSCopySchedule_m02_registration',
    @freq_type = 4, @freq_interval = 1, @freq_subday_type = 4, @freq_subday_interval = 1,
    @active_start_time = 0, @schedule_id = @s1 OUTPUT;
EXEC msdb.dbo.sp_attach_schedule @job_id = @copy_job, @schedule_id = @s1;
EXEC msdb.dbo.sp_add_schedule @schedule_name = N'LSRestoreSchedule_m02_registration',
    @freq_type = 4, @freq_interval = 1, @freq_subday_type = 4, @freq_subday_interval = 1,
    @active_start_time = 0, @schedule_id = @s2 OUTPUT;
EXEC msdb.dbo.sp_attach_schedule @job_id = @restore_job, @schedule_id = @s2;
EXEC @rc = master.dbo.sp_add_log_shipping_secondary_database
    @secondary_database = N'm02_registration',
    @primary_server = N'hadrlab2', @primary_database = N'm02_registration',
    @restore_mode = 1, @disconnect_users = 1,
    @restore_threshold = 45, @threshold_alert_enabled = 1;
IF @rc <> 0 THROW 50000, N'sp_add_log_shipping_secondary_database failed', 1;
EXEC msdb.dbo.sp_update_job @job_id = @copy_job, @enabled = 1;
EXEC msdb.dbo.sp_update_job @job_id = @restore_job, @enabled = 1;
GO
SELECT name AS job, enabled FROM msdb.dbo.sysjobs WHERE name LIKE N'LS%' ORDER BY name;
SELECT name, state_desc AS state FROM sys.databases WHERE name = N'm02_registration';
GO
SQL
echo
echo "3. A batch written on hadrlab2, shipped to hadrlab1:"
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; EXEC m02_registration.dbo.m02_register 15, 'm02 batch reversed';"
run_job hadrlab2 LSBackup_m02_registration
run_job hadrlab1 LSCopy_m02_registration
run_job hadrlab1 LSRestore_m02_registration
count="SET NOCOUNT ON; SELECT CONCAT(@@SERVERNAME, ': ', CAST(DATABASEPROPERTYEX(N'm02_registration', 'Status') AS nvarchar(20)),
    IIF(CAST(DATABASEPROPERTYEX(N'm02_registration', 'IsInStandBy') AS int) = 1, N' STANDBY', N''), ', ',
    COUNT(*), ' rows of m02 batch reversed')
    FROM m02_registration.Enrollment.Enrollment WHERE OrderReference = 'm02 batch reversed';"
sql hadrlab2 -h -1 -Q "$count"
sql hadrlab1 -h -1 -Q "$count"
echo
echo "hadrlab1, what its copy and restore jobs did since they exist (the shared folder still holds the"
echo "log backups that hadrlab1 took itself before the failover):"
sql hadrlab1 -h -1 -s '|' <<'SQL'
SET NOCOUNT ON;
SELECT CONCAT(SUM(IIF(agent_type = 1 AND message LIKE N'Copying log backup file to%', 1, 0)), ' files copied, ',
              SUM(IIF(agent_type = 2 AND message LIKE N'Skipped log backup file%', 1, 0)), ' skipped by the restore, ',
              SUM(IIF(agent_type = 2 AND message LIKE N'Restored log backup file%', 1, 0)), ' restored')
FROM msdb.dbo.log_shipping_monitor_history_detail
WHERE agent_id IN (SELECT primary_id FROM msdb.dbo.log_shipping_primary_databases
                   WHERE primary_database = N'm02_registration'
                   UNION ALL SELECT secondary_id FROM msdb.dbo.log_shipping_secondary
                   WHERE primary_database = N'm02_registration');
-- The log restores of hadrlab1, and the server that took each backup.
SELECT CONVERT(varchar(19), r.restore_date, 120), r.restore_type, b.server_name,
       REPLACE(f.physical_device_name, N'/var/opt/mssql/logship-copy/m02_registration', N'<copy>')
FROM msdb.dbo.restorehistory AS r
JOIN msdb.dbo.backupset AS b ON b.backup_set_id = r.backup_set_id
JOIN msdb.dbo.backupmediafamily AS f ON f.media_set_id = b.media_set_id
WHERE r.destination_database_name = N'm02_registration' AND r.restore_type = 'L'
ORDER BY r.restore_history_id;
SQL
