#!/usr/bin/env bash
# Exercise of module 3, starting state. Makes sure the group AgPacha exists, as module 3
# leaves it before its cleanup (setup/ag-create.sh with PachadataTraining when it is
# missing), removes what a previous attempt left (ex_inscriptions out of the group and
# dropped on the three instances, its backup history, its folder), then creates on hadrlab1
# the database ex_inscriptions in the full recovery model, never backed up: a table
# dbo.Registration of 100 rows, and the empty folder /var/opt/mssql/share/ex_inscriptions for
# its backups. Run it again to start over.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
if [ "$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.availability_groups WHERE name = N'AgPacha'" | tr -d '[:space:]')" = 0 ]; then
    echo "AgPacha is missing: creating it with PachadataTraining (setup/ag-create.sh)."
    bash setup/ag-create.sh AgPacha PachadataTraining
fi
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
IF EXISTS (SELECT * FROM sys.availability_databases_cluster WHERE database_name = N'ex_inscriptions')
    ALTER AVAILABILITY GROUP AgPacha REMOVE DATABASE ex_inscriptions;
SQL
for n in $nodes; do
    sql $n -h -1 <<'SQL'
SET NOCOUNT ON;
-- A secondary copy leaves the group some 20 seconds after REMOVE DATABASE on the primary:
-- wait for it, at most a minute, without touching the database.
DECLARE @t0 datetime2 = SYSDATETIME();
WHILE EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states
              WHERE is_local = 1 AND database_id = DB_ID(N'ex_inscriptions'))
      AND DATEDIFF(second, @t0, SYSDATETIME()) < 60
    WAITFOR DELAY '00:00:01';
IF EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states
           WHERE is_local = 1 AND database_id = DB_ID(N'ex_inscriptions'))
    THROW 50000, N'ex_inscriptions is still joined to the group after a minute', 1;
IF DB_ID(N'ex_inscriptions') IS NOT NULL
BEGIN
    IF DATABASEPROPERTYEX(N'ex_inscriptions', 'Status') = N'ONLINE'
        ALTER DATABASE ex_inscriptions SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ex_inscriptions;
END;
DECLARE @ids TABLE (id int PRIMARY KEY);
INSERT @ids SELECT restore_history_id FROM msdb.dbo.restorehistory
WHERE destination_database_name = N'ex_inscriptions';
DELETE msdb.dbo.restorefile WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorefilegroup WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorehistory WHERE restore_history_id IN (SELECT id FROM @ids);
IF EXISTS (SELECT * FROM msdb.dbo.backupset WHERE database_name = N'ex_inscriptions')
    EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'ex_inscriptions';
SQL
done
$engine exec -u 0 hadrlab1 rm -rf /var/opt/mssql/share/ex_inscriptions
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
CREATE DATABASE ex_inscriptions;
ALTER DATABASE ex_inscriptions SET RECOVERY FULL;
GO
USE ex_inscriptions;
CREATE TABLE dbo.Registration (
    id int IDENTITY PRIMARY KEY,
    label varchar(50) NOT NULL,
    written_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
INSERT dbo.Registration (label)
SELECT TOP (100) CONCAT('start ', ROW_NUMBER() OVER (ORDER BY (SELECT NULL)))
FROM sys.all_objects;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/ex_inscriptions';
SELECT DB_NAME() AS database_name, DATABASEPROPERTYEX(DB_NAME(), 'Recovery') AS recovery_model,
       COUNT(*) AS registrations FROM dbo.Registration;
GO
SQL
