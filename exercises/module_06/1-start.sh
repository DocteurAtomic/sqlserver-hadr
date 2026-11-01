#!/usr/bin/env bash
# Exercise of module 6, starting state. Removes what a previous attempt left (the group
# AgBascule dropped wherever it is, whatever the roles, then ex_bascule dropped on the three
# instances, with its backup and restore history and its folder), then creates on hadrlab1 the
# database ex_bascule, in the full recovery model, with a full backup:
#   dbo.Registration, where the batch writes, with the instance that wrote each row.
# Then the group AgBascule, without a cluster, two replicas: hadrlab1 primary, hadrlab2 in
# synchronous commit, manual failover, automatic seeding (hadrlab3 is not in it). The script
# waits until the copy of hadrlab2 is SYNCHRONIZED (at most five minutes), then writes on
# hadrlab1 the batch "before failover", 500 rows. AgPacha, the group of the demos, is not
# touched. Run it again to start over.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
for pass in secondaries primary; do
    for n in hadrlab1 hadrlab2 hadrlab3; do
        sql $n -h -1 -v PASS="$pass" <<'SQL'
SET NOCOUNT ON;
IF N'$(PASS)' = N'secondaries' AND EXISTS (
    SELECT * FROM sys.availability_groups AS g
    JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.group_id = g.group_id
    WHERE g.name = N'AgBascule' AND rs.is_local = 1 AND rs.role_desc = N'PRIMARY')
    RETURN;
IF EXISTS (SELECT * FROM sys.availability_groups WHERE name = N'AgBascule')
    DROP AVAILABILITY GROUP AgBascule;
SQL
    done
done
for n in $nodes; do
    sql $n -h -1 <<'SQL'
SET NOCOUNT ON;
IF DB_ID(N'ex_bascule') IS NOT NULL
BEGIN
    IF DATABASEPROPERTYEX(N'ex_bascule', 'Status') = N'ONLINE'
       AND DATABASEPROPERTYEX(N'ex_bascule', 'Updateability') = N'READ_WRITE'
        ALTER DATABASE ex_bascule SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ex_bascule;
END;
DECLARE @ids TABLE (id int PRIMARY KEY);
INSERT @ids SELECT restore_history_id FROM msdb.dbo.restorehistory WHERE destination_database_name = N'ex_bascule';
DELETE msdb.dbo.restorefile WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorefilegroup WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorehistory WHERE restore_history_id IN (SELECT id FROM @ids);
IF EXISTS (SELECT * FROM msdb.dbo.backupset WHERE database_name = N'ex_bascule')
    EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'ex_bascule';
SQL
done
$engine exec -u 0 hadrlab1 rm -rf /var/opt/mssql/share/ex_bascule
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
CREATE DATABASE ex_bascule;
ALTER DATABASE ex_bascule SET RECOVERY FULL;
GO
USE ex_bascule;
CREATE TABLE dbo.Registration (
    id int IDENTITY PRIMARY KEY,
    batch varchar(20) NOT NULL,
    email varchar(100) NOT NULL,
    written_on sysname NOT NULL DEFAULT @@SERVERNAME,
    written_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
GO
USE master;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/ex_bascule';
BACKUP DATABASE ex_bascule TO DISK = N'/var/opt/mssql/share/ex_bascule/ex_bascule-full.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
CREATE AVAILABILITY GROUP AgBascule
WITH (CLUSTER_TYPE = NONE)
FOR DATABASE ex_bascule
REPLICA ON
    N'hadrlab1' WITH (ENDPOINT_URL = N'tcp://hadrlab1:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
                      FAILOVER_MODE = MANUAL, SEEDING_MODE = AUTOMATIC),
    N'hadrlab2' WITH (ENDPOINT_URL = N'tcp://hadrlab2:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
                      FAILOVER_MODE = MANUAL, SEEDING_MODE = AUTOMATIC);
GO
SQL
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; ALTER AVAILABILITY GROUP AgBascule JOIN WITH (CLUSTER_TYPE = NONE);
ALTER AVAILABILITY GROUP AgBascule GRANT CREATE ANY DATABASE;"
wait_ag_database hadrlab1 AgBascule ex_bascule 300
sql hadrlab1 -Q "SET NOCOUNT ON;
INSERT ex_bascule.dbo.Registration (batch, email)
SELECT TOP (500) 'before failover', CONCAT('user', ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), '@pachadata.example')
FROM sys.all_objects;
SELECT ar.replica_server_name AS replica, rs.role_desc AS role, ar.availability_mode_desc AS mode,
       d.synchronization_state_desc AS sync
FROM sys.availability_replicas AS ar
JOIN sys.availability_groups AS g ON g.group_id = ar.group_id AND g.name = N'AgBascule'
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id AND d.database_id = DB_ID(N'ex_bascule')
ORDER BY ar.replica_server_name;
SELECT batch, COUNT(*) AS rows_written FROM ex_bascule.dbo.Registration GROUP BY batch;"
