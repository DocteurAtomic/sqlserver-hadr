#!/usr/bin/env bash
# Module 3, setup. Removes what a previous run left (99-cleanup.sh), checks that
# PachadataTraining is on hadrlab1 alone, outside any group, in the full recovery model with
# its full backup (what setup/install.sh leaves), then creates on hadrlab1 the database
# m03_signup: a new database in the full recovery model that has never been backed up, a
# table dbo.Signup of 50 rows. It stands for the new application that the group should also
# protect, and 04-new-database.sh shows why it cannot join yet. The group itself is the demo:
# 02-create-ag.sql and 03-join.sh create it. Run it again to start over.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash demos/module_03/99-cleanup.sh >/dev/null
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
IF DATABASEPROPERTYEX(N'PachadataTraining', 'Recovery') <> N'FULL'
   OR (SELECT last_log_backup_lsn FROM sys.database_recovery_status
       WHERE database_id = DB_ID(N'PachadataTraining')) IS NULL
    THROW 50000, N'PachadataTraining is not in the state of setup/install.sh: run it again', 1;
CREATE DATABASE m03_signup;
ALTER DATABASE m03_signup SET RECOVERY FULL;
GO
USE m03_signup;
CREATE TABLE dbo.Signup (
    id int IDENTITY PRIMARY KEY,
    email varchar(100) NOT NULL,
    signed_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
INSERT dbo.Signup (email)
SELECT TOP (50) CONCAT('user', ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), '@pachadata.example')
FROM sys.all_objects;
GO
SELECT d.name, d.recovery_model_desc AS recovery_model,
       ISNULL(CAST(r.last_log_backup_lsn AS varchar(30)), 'NULL') AS last_log_backup_lsn
FROM sys.databases AS d JOIN sys.database_recovery_status AS r ON r.database_id = d.database_id
WHERE d.name IN (N'PachadataTraining', N'm03_signup') ORDER BY d.name;
SELECT COUNT(*) AS signups FROM m03_signup.dbo.Signup;
GO
SQL
