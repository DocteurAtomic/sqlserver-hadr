#!/usr/bin/env bash
# Module 10, setup. Removes what a previous run left (99-cleanup.sh), checks that
# PachadataTraining is on hadrlab1 alone, outside any group, in the full recovery model with its
# full backup (what setup/install.sh leaves), then creates on hadrlab1 the two databases of the
# module, in the full recovery model, each with a full backup on the shared volume:
#   m10_registration: dbo.Registration (100 rows) for clip 10.1, dbo.Contact (200 000 rows)
#   and dbo.Visit (1 000 000 rows) for the index maintenance of clips 10.2 and 10.3;
#   m10_archive: dbo.Archive (100 rows), added to the group and removed from it in clip 10.1.
# Then creates the group AgPacha as module 3 builds it (setup/ag-create.sh: hadrlab1 primary,
# hadrlab2 in synchronous commit, hadrlab3 in asynchronous commit) for m10_registration alone.
# PachadataTraining stays out of the group. Run it again to start over.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash demos/module_10/99-cleanup.sh >/dev/null
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
IF DATABASEPROPERTYEX(N'PachadataTraining', 'Recovery') <> N'FULL'
   OR (SELECT last_log_backup_lsn FROM sys.database_recovery_status
       WHERE database_id = DB_ID(N'PachadataTraining')) IS NULL
    THROW 50000, N'PachadataTraining is not in the state of setup/install.sh: run it again', 1;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/m10';
CREATE DATABASE m10_registration;
ALTER DATABASE m10_registration SET RECOVERY FULL;
ALTER DATABASE m10_registration MODIFY FILE (NAME = m10_registration_log, SIZE = 512MB);
CREATE DATABASE m10_archive;
ALTER DATABASE m10_archive SET RECOVERY FULL;
GO
USE m10_registration;
CREATE TABLE dbo.Registration (
    id int IDENTITY PRIMARY KEY,
    label varchar(40) NOT NULL,
    email varchar(100) NOT NULL,
    written_on sysname NOT NULL DEFAULT @@SERVERNAME,
    written_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
INSERT dbo.Registration (label, email)
SELECT TOP (100) 'setup', CONCAT('user', ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), '@pachadata.example')
FROM sys.all_objects;
CREATE TABLE dbo.Contact (
    id int NOT NULL CONSTRAINT pk_Contact PRIMARY KEY,
    last_name nvarchar(50) NOT NULL,
    email varchar(100) NOT NULL);
WITH n AS (SELECT TOP (200000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
           FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b)
INSERT dbo.Contact (id, last_name, email)
SELECT i, CONCAT(N'Name', i), CONCAT('contact', i, '@pachadata.example') FROM n;
CREATE TABLE dbo.Visit (
    id int NOT NULL CONSTRAINT pk_Visit PRIMARY KEY,
    contact_id int NOT NULL,
    visited_at datetime2(0) NOT NULL,
    page char(100) NOT NULL);
WITH n AS (SELECT TOP (1000000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
           FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b)
INSERT dbo.Visit (id, contact_id, visited_at, page)
SELECT i, i % 200000 + 1, DATEADD(second, i, '2026-01-01'), CONCAT('/sessions/', i % 500) FROM n;
GO
USE m10_archive;
CREATE TABLE dbo.Archive (id int IDENTITY PRIMARY KEY, label varchar(40) NOT NULL);
INSERT dbo.Archive (label) SELECT TOP (100) 'setup' FROM sys.all_objects;
GO
USE master;
BACKUP DATABASE m10_registration TO DISK = N'/var/opt/mssql/share/m10/m10_registration-setup.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
BACKUP DATABASE m10_archive TO DISK = N'/var/opt/mssql/share/m10/m10_archive-setup.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
GO
SQL
bash setup/ag-create.sh AgPacha m10_registration
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, rs.role_desc AS role, ar.availability_mode_desc AS mode,
       DB_NAME(d.database_id) AS db, d.synchronization_state_desc AS sync
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
ORDER BY ar.replica_server_name;
SQL
