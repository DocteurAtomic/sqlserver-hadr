#!/usr/bin/env bash
# Exercise of module 2, a solution. Run after 1-start.sh. Sets up the log shipping of
# ex_logship from hadrlab1 to hadrlab3 (full backup restored WITH NORECOVERY, jobs every five
# minutes, restore in STANDBY), writes the row 'probe' and runs the three jobs in order
# instead of waiting for their schedules, then fails over to hadrlab3 without loss and writes
# the row 'after failover' there. Other solutions hold too: check.sh reads the state.
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
echo "1. hadrlab1: the full backup, and the primary."
sql hadrlab1 <<'SQL'
USE master;
SET NOCOUNT ON;
BACKUP DATABASE ex_logship TO DISK = N'/var/opt/mssql/share/ex_logship/ex_logship-full.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
GO
DECLARE @job uniqueidentifier, @id uniqueidentifier, @schedule int, @rc int;
EXEC @rc = master.dbo.sp_add_log_shipping_primary_database
    @database = N'ex_logship',
    @backup_directory = N'/var/opt/mssql/share/logship/ex_logship',
    @backup_share = N'/var/opt/mssql/share/logship/ex_logship',
    @backup_job_name = N'LSBackup_ex_logship',
    @backup_retention_period = 4320, @backup_compression = 1,
    @backup_threshold = 15, @threshold_alert_enabled = 1,
    @backup_job_id = @job OUTPUT, @primary_id = @id OUTPUT;
IF @rc <> 0 THROW 50000, N'sp_add_log_shipping_primary_database failed', 1;
EXEC msdb.dbo.sp_add_schedule @schedule_name = N'LSBackupSchedule_ex_logship',
    @freq_type = 4, @freq_interval = 1, @freq_subday_type = 4, @freq_subday_interval = 5,
    @active_start_time = 0, @schedule_id = @schedule OUTPUT;
EXEC msdb.dbo.sp_attach_schedule @job_id = @job, @schedule_id = @schedule;
EXEC msdb.dbo.sp_update_job @job_id = @job, @enabled = 1;
EXEC master.dbo.sp_add_log_shipping_primary_secondary
    @primary_database = N'ex_logship', @secondary_server = N'hadrlab3',
    @secondary_database = N'ex_logship';
GO
SQL
echo "2. hadrlab3: the restore WITH NORECOVERY, and the secondary."
sql hadrlab3 <<'SQL'
USE master;
SET NOCOUNT ON;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/logship-copy/ex_logship';
RESTORE DATABASE ex_logship FROM DISK = N'/var/opt/mssql/share/ex_logship/ex_logship-full.bak'
    WITH NORECOVERY, CHECKSUM;
GO
DECLARE @copy uniqueidentifier, @restore uniqueidentifier, @id uniqueidentifier, @s1 int, @s2 int, @rc int;
EXEC @rc = master.dbo.sp_add_log_shipping_secondary_primary
    @primary_server = N'hadrlab1', @primary_database = N'ex_logship',
    @backup_source_directory = N'/var/opt/mssql/share/logship/ex_logship',
    @backup_destination_directory = N'/var/opt/mssql/logship-copy/ex_logship',
    @copy_job_name = N'LSCopy_ex_logship', @restore_job_name = N'LSRestore_ex_logship',
    @file_retention_period = 4320,
    @copy_job_id = @copy OUTPUT, @restore_job_id = @restore OUTPUT, @secondary_id = @id OUTPUT;
IF @rc <> 0 THROW 50000, N'sp_add_log_shipping_secondary_primary failed', 1;
-- Copy two minutes after the backup, restore two minutes after the copy.
EXEC msdb.dbo.sp_add_schedule @schedule_name = N'LSCopySchedule_ex_logship',
    @freq_type = 4, @freq_interval = 1, @freq_subday_type = 4, @freq_subday_interval = 5,
    @active_start_time = 200, @schedule_id = @s1 OUTPUT;
EXEC msdb.dbo.sp_attach_schedule @job_id = @copy, @schedule_id = @s1;
EXEC msdb.dbo.sp_add_schedule @schedule_name = N'LSRestoreSchedule_ex_logship',
    @freq_type = 4, @freq_interval = 1, @freq_subday_type = 4, @freq_subday_interval = 5,
    @active_start_time = 400, @schedule_id = @s2 OUTPUT;
EXEC msdb.dbo.sp_attach_schedule @job_id = @restore, @schedule_id = @s2;
EXEC @rc = master.dbo.sp_add_log_shipping_secondary_database
    @secondary_database = N'ex_logship', @primary_server = N'hadrlab1', @primary_database = N'ex_logship',
    @restore_mode = 1, @disconnect_users = 1, @restore_threshold = 15, @threshold_alert_enabled = 1;
IF @rc <> 0 THROW 50000, N'sp_add_log_shipping_secondary_database failed', 1;
EXEC msdb.dbo.sp_update_job @job_id = @copy, @enabled = 1;
EXEC msdb.dbo.sp_update_job @job_id = @restore, @enabled = 1;
GO
SQL
echo "3. The row 'probe', shipped by the three jobs run in order."
sql hadrlab1 -Q "SET NOCOUNT ON; INSERT ex_logship.dbo.Registration (label) VALUES ('probe');"
run_job hadrlab1 LSBackup_ex_logship
run_job hadrlab3 LSCopy_ex_logship
run_job hadrlab3 LSRestore_ex_logship
sql hadrlab3 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT('hadrlab3, STANDBY: ', COUNT(*), ' row probe')
    FROM ex_logship.dbo.Registration WHERE label = 'probe';"
echo "4. The planned failover to hadrlab3."
sql hadrlab1 -Q "SET NOCOUNT ON; INSERT ex_logship.dbo.Registration (label) VALUES ('last before failover');"
disable_job hadrlab1 LSBackup_ex_logship
run_job hadrlab3 LSCopy_ex_logship
run_job hadrlab3 LSRestore_ex_logship
disable_job hadrlab3 LSCopy_ex_logship
disable_job hadrlab3 LSRestore_ex_logship
sql hadrlab1 -Q "SET NOCOUNT ON; BACKUP LOG ex_logship TO DISK = N'/var/opt/mssql/share/logship/ex_logship_tail.trn'
    WITH INIT, NORECOVERY, COMPRESSION, CHECKSUM;"
sql hadrlab3 -Q "SET NOCOUNT ON; RESTORE LOG ex_logship FROM DISK = N'/var/opt/mssql/share/logship/ex_logship_tail.trn'
    WITH RECOVERY, CHECKSUM;
    INSERT ex_logship.dbo.Registration (label) VALUES ('after failover');
    SELECT label, COUNT(*) AS n FROM ex_logship.dbo.Registration WHERE label NOT LIKE 'start%'
    GROUP BY label ORDER BY MIN(id);"
