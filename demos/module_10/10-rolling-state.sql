-- ci: skip (Windows cluster of the course, not the containers)
-- Runs on either node of the cluster, in sqlcmd. Module 10, clip 10.4: before and after each
-- step of the rolling update of Pacha, the version of this instance, the replicas of the group
-- with their failover mode and health, and the state of each copy of each database.
SET NOCOUNT ON;
SELECT @@SERVERNAME AS node, CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(20)) AS version,
       CAST(SERVERPROPERTY('ProductUpdateLevel') AS nvarchar(20)) AS update_level,
       CAST(SERVERPROPERTY('ProductUpdateReference') AS nvarchar(20)) AS kb;
SELECT g.name AS ag, ags.primary_replica, ags.synchronization_health_desc AS group_health
FROM sys.availability_groups AS g
JOIN sys.dm_hadr_availability_group_states AS ags ON ags.group_id = g.group_id;
SELECT ar.replica_server_name AS replica, ISNULL(rs.role_desc, N'-') AS role,
       ar.availability_mode_desc AS mode, ar.failover_mode_desc AS failover,
       ISNULL(rs.connected_state_desc, N'-') AS connected, ISNULL(rs.synchronization_health_desc, N'-') AS health
FROM sys.availability_replicas AS ar
LEFT JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
ORDER BY ar.replica_server_name;
SELECT DB_NAME(d.database_id) AS db, ar.replica_server_name AS replica, d.synchronization_state_desc AS sync,
       d.is_suspended AS suspended, ISNULL(d.suspend_reason_desc, N'-') AS reason
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
ORDER BY db, replica;
