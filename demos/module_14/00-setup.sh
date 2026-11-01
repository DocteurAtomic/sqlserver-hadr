#!/usr/bin/env bash
# Module 14, setup. Removes what a previous run left (99-cleanup.sh), checks that
# PachadataTraining is on hadrlab1 alone, outside any group, in the full recovery model with
# its full backup (what setup/install.sh leaves), then creates on hadrlab1 the database of the
# module, m14_registration, in the full recovery model, with a full backup on the shared volume:
# dbo.Registration, 100 registrations, each row saying on which instance it was written. No
# group yet: 01-two-sites.sh builds the two groups and the distributed group, as Learn writes
# them. PachadataTraining stays out of every group of this module. Run it again to start over.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash demos/module_14/99-cleanup.sh >/dev/null
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
IF DATABASEPROPERTYEX(N'PachadataTraining', 'Recovery') <> N'FULL'
   OR (SELECT last_log_backup_lsn FROM sys.database_recovery_status
       WHERE database_id = DB_ID(N'PachadataTraining')) IS NULL
    THROW 50000, N'PachadataTraining is not in the state of setup/install.sh: run it again', 1;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/m14';
CREATE DATABASE m14_registration;
ALTER DATABASE m14_registration SET RECOVERY FULL;
GO
USE m14_registration;
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
BACKUP DATABASE m14_registration TO DISK = N'/var/opt/mssql/share/m14/m14_registration-setup.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
GO
SELECT DB_NAME(database_id) AS db, recovery_model_desc AS recovery,
       (SELECT COUNT(*) FROM m14_registration.dbo.Registration) AS registrations
FROM sys.databases WHERE name = N'm14_registration';
SQL
