-- ci: skip (Windows cluster of the course, not the containers)
-- Runs on SQL01, primary of Pacha again, in sqlcmd, after clip 10.4: puts the failover mode
-- of both replicas back to AUTOMATIC if a run stopped halfway, removes m10_rolling from Pacha
-- and drops it, with its backup history. Then, on SQL02: DROP DATABASE m10_rolling;
-- (its copy stays there in RESTORING once removed from the group).
SET NOCOUNT ON;
ALTER AVAILABILITY GROUP Pacha MODIFY REPLICA ON N'SQL01' WITH (FAILOVER_MODE = AUTOMATIC);
ALTER AVAILABILITY GROUP Pacha MODIFY REPLICA ON N'SQL02' WITH (FAILOVER_MODE = AUTOMATIC);
IF EXISTS (SELECT * FROM sys.availability_databases_cluster WHERE database_name = N'm10_rolling')
    ALTER AVAILABILITY GROUP Pacha REMOVE DATABASE m10_rolling;
IF DB_ID(N'm10_rolling') IS NOT NULL DROP DATABASE m10_rolling;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'm10_rolling';
SELECT replica_server_name AS replica, failover_mode_desc AS failover FROM sys.availability_replicas ORDER BY 1;
