#!/usr/bin/env bash
# Module 6, setup. Removes what a previous run left (99-cleanup.sh), checks that
# PachadataTraining is on hadrlab1 alone, outside any group, in the full recovery model with
# its full backup (what setup/install.sh leaves), then creates on hadrlab1 the database of the
# module, m06_registration, in the full recovery model, with a full backup on the shared
# volume: dbo.Registration, 100 registrations, each row with a label that says when it was
# written. Then creates the group AgPacha as module 3 builds it (setup/ag-create.sh: hadrlab1
# primary, hadrlab2 in synchronous commit, hadrlab3 in asynchronous commit) for m06_registration
# alone, and waits until both copies are caught up. PachadataTraining stays out of the group:
# the failovers of this module, the forced one included, only move m06_registration. Run it
# again to start over.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash demos/module_06/99-cleanup.sh >/dev/null
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
IF DATABASEPROPERTYEX(N'PachadataTraining', 'Recovery') <> N'FULL'
   OR (SELECT last_log_backup_lsn FROM sys.database_recovery_status
       WHERE database_id = DB_ID(N'PachadataTraining')) IS NULL
    THROW 50000, N'PachadataTraining is not in the state of setup/install.sh: run it again', 1;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/m06';
CREATE DATABASE m06_registration;
ALTER DATABASE m06_registration SET RECOVERY FULL;
GO
USE m06_registration;
CREATE TABLE dbo.Registration (
    id int IDENTITY PRIMARY KEY,
    label varchar(40) NOT NULL,
    email varchar(100) NOT NULL,
    written_on sysname NOT NULL DEFAULT @@SERVERNAME,
    written_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
INSERT dbo.Registration (label, email)
SELECT TOP (100) 'setup', CONCAT('user', ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), '@pachadata.example')
FROM sys.all_objects;
GO
USE master;
BACKUP DATABASE m06_registration TO DISK = N'/var/opt/mssql/share/m06/m06_registration-setup.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
GO
SQL
bash setup/ag-create.sh AgPacha m06_registration
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, rs.role_desc AS role, ar.availability_mode_desc AS mode,
       DB_NAME(d.database_id) AS db, d.synchronization_state_desc AS sync
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
ORDER BY ar.replica_server_name;
SQL
