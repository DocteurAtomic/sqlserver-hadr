-- ci: skip (Windows cluster of the course, not the containers)
-- Runs on SQL01, primary of Pacha again, in sqlcmd, after the demos of module 8: puts back
-- the settings that the demos change (DB_FAILOVER, REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT),
-- removes m08_registrations from Pacha and drops it, with its backup history. Then, on SQL02:
-- DROP DATABASE m08_registrations; and 99-cleanup-cluster.ps1 on both nodes.
SET NOCOUNT ON;
ALTER AVAILABILITY GROUP Pacha SET (DB_FAILOVER = OFF);
ALTER AVAILABILITY GROUP Pacha SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0);
ALTER AVAILABILITY GROUP Pacha REMOVE DATABASE m08_registrations;
WAITFOR DELAY '00:00:05';
DROP DATABASE m08_registrations;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'm08_registrations';
SELECT name, db_failover, required_synchronized_secondaries_to_commit FROM sys.availability_groups;
