-- instance: SQL01
-- ci: skip (Windows cluster of the course, not the containers)
-- Module 7, clips 7.1 and 7.2: the cluster as SQL Server sees it. number_of_quorum_votes is
-- the vote assigned to a member, number_of_current_votes the vote that dynamic quorum leaves it.
-- Without quorum, sys.dm_hadr_cluster and sys.dm_hadr_cluster_members return no row.
SET NOCOUNT ON;
SELECT cluster_name, quorum_type_desc, quorum_state_desc FROM sys.dm_hadr_cluster;
SELECT member_name, member_type_desc, member_state_desc, number_of_quorum_votes, number_of_current_votes
FROM sys.dm_hadr_cluster_members;
SELECT member_name, network_subnet_ip, is_public FROM sys.dm_hadr_cluster_networks;
SELECT ag.name AS ag, ar.replica_server_name, rs.role_desc, rs.connected_state_desc,
       rs.synchronization_health_desc, ar.availability_mode_desc, ar.failover_mode_desc
FROM sys.availability_groups AS ag
JOIN sys.availability_replicas AS ar ON ar.group_id = ag.group_id
LEFT JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id;
