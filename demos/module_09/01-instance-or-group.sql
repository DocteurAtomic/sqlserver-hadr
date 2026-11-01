-- instance: SQL01 (then the same script on SQL02)
-- ci: skip (Windows cluster of the course, not the containers)
-- Module 9, clips 9.1 and 9.2: is this instance a failover cluster instance (FCI)? A node of an
-- availability group is a member of the cluster, but its instance is not a cluster resource:
-- IsClustered is 0 and the FCI views (cluster nodes, shared drives) return no row. The last
-- query, for clip 9.2: the group Pacha is a contained availability group.
SET NOCOUNT ON;
SELECT CAST(SERVERPROPERTY('ServerName') AS sysname) AS server_name,
       CAST(SERVERPROPERTY('ComputerNamePhysicalNetBIOS') AS sysname) AS physical_node,
       SERVERPROPERTY('IsClustered') AS is_clustered,
       SERVERPROPERTY('IsHadrEnabled') AS is_hadr_enabled,
       SERVERPROPERTY('HadrManagerStatus') AS hadr_manager_status,
       CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(260)) AS default_data_path;
SELECT COUNT(*) AS fci_nodes FROM sys.dm_os_cluster_nodes;
SELECT COUNT(*) AS fci_shared_drives FROM sys.dm_io_cluster_shared_drives;
SELECT cluster_name, quorum_type_desc, quorum_state_desc FROM sys.dm_hadr_cluster;
SELECT member_name, member_type_desc, member_state_desc, number_of_quorum_votes, number_of_current_votes
FROM sys.dm_hadr_cluster_members;
SELECT name, cluster_type_desc, is_contained FROM sys.availability_groups;
