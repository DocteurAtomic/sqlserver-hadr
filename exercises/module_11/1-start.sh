#!/usr/bin/env bash
# Exercise of module 11, starting state. Removes what a previous attempt left (the group
# AgObjects dropped wherever it is, whatever the roles; then, on the three instances, ex_objects
# and its history, the login ex_app and the job ex_heartbeat), then builds on hadrlab1 what an
# application installed there would leave:
#   - the database ex_objects, full recovery, full backup: dbo.Heartbeat, where the job writes
#     the instance it ran on;
#   - the SQL login ex_app (password Ex-App-2026!), and its user in ex_objects, reader and writer;
#   - the job ex_heartbeat, owned by sa, one step in ex_objects that inserts a row into
#     dbo.Heartbeat, no schedule.
# Then the group AgObjects, without a cluster, two replicas: hadrlab1 primary, hadrlab2 in
# synchronous commit, automatic seeding (hadrlab3 is not in it). The job runs once on hadrlab1.
# Then the planned failover to hadrlab2 (setup/ag-failover.sh). From there, the application is
# refused on hadrlab2 and the job is missing there. AgPacha, the group of the demos, is not
# touched. Run it again to start over.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
for pass in secondaries primary; do
    for n in $nodes; do
        sql $n -h -1 -v PASS="$pass" <<'SQL'
SET NOCOUNT ON;
IF N'$(PASS)' = N'secondaries' AND EXISTS (
    SELECT * FROM sys.availability_groups AS g
    JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.group_id = g.group_id
    WHERE g.name = N'AgObjects' AND rs.is_local = 1 AND rs.role_desc = N'PRIMARY')
    RETURN;
IF EXISTS (SELECT * FROM sys.availability_groups WHERE name = N'AgObjects')
    DROP AVAILABILITY GROUP AgObjects;
SQL
    done
done
for n in $nodes; do
    sql $n -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @q nvarchar(max) = N'';
IF DB_ID(N'ex_objects') IS NOT NULL
BEGIN
    IF DATABASEPROPERTYEX(N'ex_objects', 'Status') = N'ONLINE'
       AND DATABASEPROPERTYEX(N'ex_objects', 'Updateability') = N'READ_WRITE'
        ALTER DATABASE ex_objects SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ex_objects;
END;
DECLARE @ids TABLE (id int PRIMARY KEY);
INSERT @ids SELECT restore_history_id FROM msdb.dbo.restorehistory WHERE destination_database_name = N'ex_objects';
DELETE msdb.dbo.restorefile WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorefilegroup WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorehistory WHERE restore_history_id IN (SELECT id FROM @ids);
IF EXISTS (SELECT * FROM msdb.dbo.backupset WHERE database_name = N'ex_objects')
    EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'ex_objects';
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'ex_heartbeat')
    EXEC msdb.dbo.sp_delete_job @job_name = N'ex_heartbeat', @delete_history = 1;
IF SUSER_ID(N'ex_app') IS NOT NULL
BEGIN
    SELECT @q += N'KILL ' + CAST(session_id AS nvarchar(10)) + N'; ' FROM sys.dm_exec_sessions WHERE login_name = N'ex_app';
    EXEC (@q);
    DROP LOGIN ex_app;
END;
SQL
done
$engine exec -u 0 hadrlab1 rm -rf /var/opt/mssql/share/ex_objects
sql hadrlab1 -h -1 <<'SQL' | { grep -v '^Processed \|^BACKUP DATABASE successfully\|^Changed database' || true; }
SET NOCOUNT ON;
CREATE DATABASE ex_objects;
ALTER DATABASE ex_objects SET RECOVERY FULL;
GO
USE ex_objects;
CREATE TABLE dbo.Heartbeat (
    id int IDENTITY PRIMARY KEY,
    written_on sysname NOT NULL DEFAULT @@SERVERNAME,
    written_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
GO
USE master;
CREATE LOGIN ex_app WITH PASSWORD = N'Ex-App-2026!', CHECK_POLICY = OFF, DEFAULT_DATABASE = ex_objects;
GO
USE ex_objects;
CREATE USER ex_app FOR LOGIN ex_app;
ALTER ROLE db_datareader ADD MEMBER ex_app;
ALTER ROLE db_datawriter ADD MEMBER ex_app;
GO
USE master;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/ex_objects';
BACKUP DATABASE ex_objects TO DISK = N'/var/opt/mssql/share/ex_objects/ex_objects-full.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
EXEC msdb.dbo.sp_add_job @job_name = N'ex_heartbeat', @owner_login_name = N'sa',
    @description = N'Exercise of module 11: writes the instance it runs on into ex_objects.dbo.Heartbeat';
EXEC msdb.dbo.sp_add_jobstep @job_name = N'ex_heartbeat', @step_name = N'heartbeat',
    @subsystem = N'TSQL', @database_name = N'ex_objects', @command = N'INSERT dbo.Heartbeat DEFAULT VALUES;';
EXEC msdb.dbo.sp_add_jobserver @job_name = N'ex_heartbeat', @server_name = N'(local)';
CREATE AVAILABILITY GROUP AgObjects
WITH (CLUSTER_TYPE = NONE)
FOR DATABASE ex_objects
REPLICA ON
    N'hadrlab1' WITH (ENDPOINT_URL = N'tcp://hadrlab1:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
                      FAILOVER_MODE = MANUAL, SEEDING_MODE = AUTOMATIC),
    N'hadrlab2' WITH (ENDPOINT_URL = N'tcp://hadrlab2:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
                      FAILOVER_MODE = MANUAL, SEEDING_MODE = AUTOMATIC);
GO
SQL
join_ag hadrlab2 AgObjects
wait_ag_database hadrlab1 AgObjects ex_objects 300
run_job hadrlab1 ex_heartbeat 60 | grep -v 'started successfully'
bash setup/ag-failover.sh AgObjects hadrlab2 | tail -1
sql hadrlab2 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, rs.role_desc AS role, d.synchronization_state_desc AS sync
FROM sys.availability_replicas AS ar
JOIN sys.availability_groups AS g ON g.group_id = ar.group_id AND g.name = N'AgObjects'
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id AND d.database_id = DB_ID(N'ex_objects')
ORDER BY ar.replica_server_name;
SELECT written_on, COUNT(*) AS heartbeats FROM ex_objects.dbo.Heartbeat GROUP BY written_on;"
