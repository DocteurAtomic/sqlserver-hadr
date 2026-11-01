#!/usr/bin/env bash
# Module 12, setup. Removes what a previous run left (99-cleanup.sh), checks that
# PachadataTraining is on hadrlab1 alone, outside any group (what setup/install.sh leaves), then
# creates on hadrlab1 the database m12_registration, in the full recovery model, with a full
# backup on the shared volume: dbo.Registration, 1,000 registrations, and a payload column wide
# enough for the loads of the demos to write a few hundred megabytes of log in a few seconds.
# Then creates the group AgPacha as module 3 builds it (setup/ag-create.sh: hadrlab1 primary,
# hadrlab2 in synchronous commit, hadrlab3 in asynchronous commit) for m12_registration alone,
# and waits until both copies are caught up, then commits one registration in the group. Run it
# again to start over.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash demos/module_12/99-cleanup.sh >/dev/null
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
IF DATABASEPROPERTYEX(N'PachadataTraining', 'Recovery') <> N'FULL'
   OR (SELECT last_log_backup_lsn FROM sys.database_recovery_status
       WHERE database_id = DB_ID(N'PachadataTraining')) IS NULL
    THROW 50000, N'PachadataTraining is not in the state of setup/install.sh: run it again', 1;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/m12';
CREATE DATABASE m12_registration;
ALTER DATABASE m12_registration SET RECOVERY FULL;
ALTER DATABASE m12_registration MODIFY FILE (NAME = m12_registration_log, SIZE = 512MB);
GO
USE m12_registration;
CREATE TABLE dbo.Registration (
    id int IDENTITY PRIMARY KEY,
    email varchar(100) NOT NULL,
    payload char(2000) NOT NULL DEFAULT '',
    written_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
INSERT dbo.Registration (email)
SELECT TOP (1000) CONCAT('user', ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), '@pachadata.example')
FROM sys.all_objects;
GO
USE master;
BACKUP DATABASE m12_registration TO DISK = N'/var/opt/mssql/share/m12/m12_registration-setup.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
SQL
bash setup/ag-create.sh AgPacha m12_registration
# One registration committed in the group: until a first commit reaches a copy, its
# last_commit_time is NULL, and setup/ag-health.sql cannot estimate its data loss.
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
INSERT m12_registration.dbo.Registration (email) VALUES ('first@pachadata.example');
WAITFOR DELAY '00:00:02';
SELECT ar.replica_server_name AS replica, rs.role_desc AS role, ar.availability_mode_desc AS mode,
       DB_NAME(d.database_id) AS db, d.synchronization_state_desc AS sync
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
ORDER BY ar.replica_server_name;
SQL
