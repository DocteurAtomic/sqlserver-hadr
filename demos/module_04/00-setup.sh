#!/usr/bin/env bash
# Module 4, setup. Removes what a previous run left (99-cleanup.sh), checks that
# PachadataTraining is on hadrlab1 alone, outside any group, in the full recovery model with
# its full backup (what setup/install.sh leaves), then creates on hadrlab1 the two databases
# of the module, in the full recovery model, each with a full backup on the shared volume:
#   m04_registration, the registrations of the site, a table dbo.Registration of 100 rows;
#   m04_solo, the same table, which stays outside any group: the commit without a replica.
# Then creates the group AgPacha as module 3 left it (setup/ag-create.sh: hadrlab2 in
# synchronous commit, hadrlab3 in asynchronous commit), for PachadataTraining and
# m04_registration, and waits until both are caught up on the two secondaries. The demos
# write in m04_registration and m04_solo, never in PachadataTraining. Run it again to start
# over.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash demos/module_04/99-cleanup.sh >/dev/null
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
IF DATABASEPROPERTYEX(N'PachadataTraining', 'Recovery') <> N'FULL'
   OR (SELECT last_log_backup_lsn FROM sys.database_recovery_status
       WHERE database_id = DB_ID(N'PachadataTraining')) IS NULL
    THROW 50000, N'PachadataTraining is not in the state of setup/install.sh: run it again', 1;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/m04';
CREATE DATABASE m04_registration;
ALTER DATABASE m04_registration SET RECOVERY FULL;
CREATE DATABASE m04_solo;
ALTER DATABASE m04_solo SET RECOVERY FULL;
GO
USE m04_registration;
CREATE TABLE dbo.Registration (
    id int IDENTITY PRIMARY KEY,
    email varchar(100) NOT NULL,
    signed_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
INSERT dbo.Registration (email)
SELECT TOP (100) CONCAT('user', ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), '@pachadata.example')
FROM sys.all_objects;
GO
USE m04_solo;
CREATE TABLE dbo.Registration (
    id int IDENTITY PRIMARY KEY,
    email varchar(100) NOT NULL,
    signed_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
INSERT dbo.Registration (email)
SELECT TOP (100) CONCAT('user', ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), '@pachadata.example')
FROM sys.all_objects;
GO
USE master;
BACKUP DATABASE m04_registration TO DISK = N'/var/opt/mssql/share/m04/m04_registration-full.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
BACKUP DATABASE m04_solo TO DISK = N'/var/opt/mssql/share/m04/m04_solo-full.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
GO
SQL
bash setup/ag-create.sh AgPacha PachadataTraining m04_registration
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, ar.availability_mode_desc AS mode, DB_NAME(d.database_id) AS db,
       d.synchronization_state_desc AS sync, d.is_commit_participant AS commit_participant
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
ORDER BY ar.replica_server_name, db;
SQL
