#!/usr/bin/env bash
# Module 5, setup. Removes what a previous run left (99-cleanup.sh), checks that
# PachadataTraining is on hadrlab1 alone, outside any group, in the full recovery model with
# its full backup (what setup/install.sh leaves), then creates on hadrlab1 the database of the
# module, m05_reports, in the full recovery model, with a full backup on the shared volume:
# dbo.Enrollment, 10,000 enrollments of fixed width, which the reports read and the demos
# update. Then creates the group AgPacha as module 3 left it (setup/ag-create.sh: hadrlab2 in
# synchronous commit, hadrlab3 in asynchronous commit, no secondary readable), for
# PachadataTraining and m05_reports, and waits until both are caught up on the two
# secondaries. The demos write in m05_reports, never in PachadataTraining. Run it again to
# start over.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash demos/module_05/99-cleanup.sh >/dev/null
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
IF DATABASEPROPERTYEX(N'PachadataTraining', 'Recovery') <> N'FULL'
   OR (SELECT last_log_backup_lsn FROM sys.database_recovery_status
       WHERE database_id = DB_ID(N'PachadataTraining')) IS NULL
    THROW 50000, N'PachadataTraining is not in the state of setup/install.sh: run it again', 1;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/m05';
CREATE DATABASE m05_reports;
ALTER DATABASE m05_reports SET RECOVERY FULL;
GO
USE m05_reports;
-- Fixed-width rows: 4 + 4 + 8 + 40 bytes of data, so that a change in the size of a record
-- shows in sys.dm_db_index_physical_stats.
CREATE TABLE dbo.Enrollment (
    id int NOT NULL PRIMARY KEY,
    session_id int NOT NULL,
    enrolled_at datetime NOT NULL,
    email char(40) NOT NULL);
INSERT dbo.Enrollment (id, session_id, enrolled_at, email)
SELECT TOP (10000) n, 1 + n % 200, DATEADD(minute, n, '20261001'), CONCAT('user', n, '@pachadata.example')
FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_columns AS a CROSS JOIN sys.all_columns AS b) AS t;
GO
USE master;
BACKUP DATABASE m05_reports TO DISK = N'/var/opt/mssql/share/m05/m05_reports-setup.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
GO
SQL
bash setup/ag-create.sh AgPacha PachadataTraining m05_reports
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, ar.availability_mode_desc AS mode,
       ar.secondary_role_allow_connections_desc AS secondary_allow, DB_NAME(d.database_id) AS db,
       d.synchronization_state_desc AS sync
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
ORDER BY ar.replica_server_name, db;
SQL
