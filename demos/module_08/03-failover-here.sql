-- ci: skip (Windows cluster of the course, not the containers)
-- Runs on the node that must become primary, in sqlcmd. Module 8, clips 8.1 and 8.2: the
-- planned failover of Pacha under the cluster, without data loss. It is refused (Msg 41142)
-- when a database of the group is not SYNCHRONIZED here, so the state is read first.
SET NOCOUNT ON;
SELECT DB_NAME(database_id) AS database_name, synchronization_state_desc
FROM sys.dm_hadr_database_replica_states WHERE is_local = 1;
SELECT CONVERT(varchar(12), SYSUTCDATETIME(), 114) AS failover_sent_utc;
ALTER AVAILABILITY GROUP Pacha FAILOVER;
SELECT CONVERT(varchar(12), SYSUTCDATETIME(), 114) AS failover_returned_utc, rs.role_desc
FROM sys.dm_hadr_availability_replica_states AS rs WHERE rs.is_local = 1;
