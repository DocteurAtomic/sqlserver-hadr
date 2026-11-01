-- ci: skip (Windows cluster of the course, not the containers)
-- Runs on either node, in sqlcmd. Module 8, clips 8.3 and 8.4: the state of each database of Pacha on
-- this instance, the role of the local replica, the DB_FAILOVER setting of the group, and
-- the state of every copy seen from here.
SET NOCOUNT ON;
SELECT CONVERT(varchar(12), SYSUTCDATETIME(), 114) AS utc, @@SERVERNAME AS instance,
       g.db_failover, rs.role_desc, rs.synchronization_health_desc
FROM sys.availability_groups AS g
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.group_id = g.group_id AND rs.is_local = 1;
SELECT d.name, d.state_desc FROM sys.databases AS d WHERE d.replica_id IS NOT NULL;
SELECT DB_NAME(drs.database_id) AS database_name, ar.replica_server_name, drs.synchronization_state_desc,
       drs.is_suspended, drs.suspend_reason_desc, drs.database_state_desc
FROM sys.dm_hadr_database_replica_states AS drs
JOIN sys.availability_replicas AS ar ON ar.replica_id = drs.replica_id
WHERE drs.database_id = DB_ID(N'm08_registrations');
