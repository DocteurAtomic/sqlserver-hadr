#!/usr/bin/env bash
# Module 11, setup. Removes what a previous run left (99-cleanup.sh), checks that
# PachadataTraining is on hadrlab1 alone, outside any group (what setup/install.sh leaves), then
# builds on hadrlab1 what an application installed there a month ago would have left:
#   - the database m11_registration, in the full recovery model, with a full backup on the
#     shared volume: dbo.Registration, 100 registrations, and dbo.Heartbeat, where a job writes
#     the instance it ran on;
#   - the SQL login of the application, m11_app (password M11-App-2026!), and its user in
#     m11_registration, a reader and writer;
#   - the SQL Server Agent job m11_heartbeat, owned by sa: one T-SQL step that runs in
#     m11_registration and inserts a row into dbo.Heartbeat, no schedule (the demos start it
#     with run_job, so that the outputs do not depend on the minute).
# Then creates the group AgPacha as module 3 builds it (setup/ag-create.sh: hadrlab1 primary,
# hadrlab2 in synchronous commit, hadrlab3 in asynchronous commit) for m11_registration alone,
# and waits until both copies are caught up. The login and the job stay on hadrlab1 only: that
# is what the module repairs. Run it again to start over.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash demos/module_11/99-cleanup.sh >/dev/null
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
IF DATABASEPROPERTYEX(N'PachadataTraining', 'Recovery') <> N'FULL'
   OR (SELECT last_log_backup_lsn FROM sys.database_recovery_status
       WHERE database_id = DB_ID(N'PachadataTraining')) IS NULL
    THROW 50000, N'PachadataTraining is not in the state of setup/install.sh: run it again', 1;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/m11';
CREATE DATABASE m11_registration;
ALTER DATABASE m11_registration SET RECOVERY FULL;
GO
USE m11_registration;
CREATE TABLE dbo.Registration (
    id int IDENTITY PRIMARY KEY,
    email varchar(100) NOT NULL,
    written_on sysname NOT NULL DEFAULT @@SERVERNAME,
    written_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
INSERT dbo.Registration (email)
SELECT TOP (100) CONCAT('user', ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), '@pachadata.example')
FROM sys.all_objects;
CREATE TABLE dbo.Heartbeat (
    id int IDENTITY PRIMARY KEY,
    written_on sysname NOT NULL DEFAULT @@SERVERNAME,
    written_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
GO
USE master;
CREATE LOGIN m11_app WITH PASSWORD = N'M11-App-2026!', CHECK_POLICY = OFF,
    DEFAULT_DATABASE = m11_registration;
GO
USE m11_registration;
CREATE USER m11_app FOR LOGIN m11_app;
ALTER ROLE db_datareader ADD MEMBER m11_app;
ALTER ROLE db_datawriter ADD MEMBER m11_app;
GO
USE master;
BACKUP DATABASE m11_registration TO DISK = N'/var/opt/mssql/share/m11/m11_registration-setup.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
EXEC msdb.dbo.sp_add_job @job_name = N'm11_heartbeat', @owner_login_name = N'sa',
    @description = N'Module 11: writes the instance it runs on into m11_registration.dbo.Heartbeat';
EXEC msdb.dbo.sp_add_jobstep @job_name = N'm11_heartbeat', @step_name = N'heartbeat',
    @subsystem = N'TSQL', @database_name = N'm11_registration',
    @command = N'INSERT dbo.Heartbeat DEFAULT VALUES;';
EXEC msdb.dbo.sp_add_jobserver @job_name = N'm11_heartbeat', @server_name = N'(local)';
GO
SQL
bash setup/ag-create.sh AgPacha m11_registration
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, rs.role_desc AS role, ar.availability_mode_desc AS mode,
       DB_NAME(d.database_id) AS db, d.synchronization_state_desc AS sync
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
ORDER BY ar.replica_server_name;
SQL
