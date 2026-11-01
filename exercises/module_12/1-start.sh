#!/usr/bin/env bash
# Exercise of module 12, start. Removes what a previous try left (the group AgHealth and the
# database ex_health on the three instances), creates ex_health on hadrlab1 (dbo.Reading, in the
# full recovery model, with a full backup) and the group AgHealth for it as module 3 builds a
# group (setup/ag-create.sh: hadrlab1 primary, hadrlab2 synchronous, hadrlab3 asynchronous).
# Then makes, on the primary, a change of the group's configuration that cuts one replica off
# AgHealth alone (the endpoints, shared by every group of an instance, are not touched), and
# writes 2,000 rows. It does not say what it changed: that is the exercise. It also starts the
# AlwaysOn_health session on the three instances, if it does not run.
# Usage: ./exercises/module_12/1-start.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash setup/ag-remove.sh AgHealth >/dev/null
for n in $nodes; do
    sql $n -h -1 <<'SQL'
SET NOCOUNT ON;
IF DB_ID(N'ex_health') IS NOT NULL
BEGIN
    IF DATABASEPROPERTYEX(N'ex_health', 'Status') = N'ONLINE'
       AND DATABASEPROPERTYEX(N'ex_health', 'Updateability') = N'READ_WRITE'
        ALTER DATABASE ex_health SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ex_health;
END;
IF EXISTS (SELECT * FROM msdb.dbo.backupset WHERE database_name = N'ex_health')
    EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'ex_health';
SQL
done
sql hadrlab1 -h -1 <<'SQL' | { grep -v -e '^Processed ' -e '^BACKUP DATABASE successfully' || true; }
SET NOCOUNT ON;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/ex_health';
CREATE DATABASE ex_health;
ALTER DATABASE ex_health SET RECOVERY FULL;
GO
CREATE TABLE ex_health.dbo.Reading (
    id int IDENTITY PRIMARY KEY,
    sensor varchar(20) NOT NULL,
    written_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
BACKUP DATABASE ex_health TO DISK = N'/var/opt/mssql/share/ex_health/ex_health.bak' WITH INIT, CHECKSUM;
SQL
bash setup/ag-create.sh AgHealth ex_health >/dev/null
# AlwaysOn_health running on the three instances, so that it records what follows (clip 12.2;
# demos/module_12/99-cleanup.sh stops it again).
for n in $nodes; do
    sql $n -h -1 -Q "SET NOCOUNT ON; IF NOT EXISTS (SELECT * FROM sys.dm_xe_sessions WHERE name = N'AlwaysOn_health')
        ALTER EVENT SESSION AlwaysOn_health ON SERVER STATE = START;"
done
# The change: hadrlab3 is now looked for on a port where nothing listens.
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
ALTER AVAILABILITY GROUP AgHealth MODIFY REPLICA ON N'hadrlab3' WITH (ENDPOINT_URL = N'tcp://hadrlab3:5023');
SQL
sleep 15
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @i int = 0;
WHILE @i < 20
BEGIN
    INSERT ex_health.dbo.Reading (sensor) SELECT TOP (100) 'probe' FROM sys.all_objects;
    SET @i += 1;
END;
SQL
echo "AgHealth is ready on hadrlab1, 2000 rows written since. Something is wrong with it: run exercises/module_12/check.sh."
