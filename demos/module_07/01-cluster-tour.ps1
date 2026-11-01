# ci: skip (Windows cluster of the course, not the containers)
# Runs on SQL01, a node of the cluster, in an elevated PowerShell (module FailoverClusters).
# Module 7, clip 7.1: the nodes, the network, the roles and their resources. The SQL Server
# service is not a cluster resource: only the availability group and its listener are.
$ProgressPreference = 'SilentlyContinue'
"== Get-Cluster"
Get-Cluster | Format-List Name, Domain, SameSubnetDelay, SameSubnetThreshold
"== Get-ClusterNode"
Get-ClusterNode | Format-Table Id, Name, State -AutoSize
"== Get-ClusterNetwork"
Get-ClusterNetwork | Format-Table Name, Role, Address, State -AutoSize
"== Get-ClusterGroup"
Get-ClusterGroup | Format-Table Name, OwnerNode, State -AutoSize
"== Get-ClusterResource"
Get-ClusterResource | Format-Table Name, ResourceType, OwnerGroup, OwnerNode, State -AutoSize
"== Get-ClusterResourceDependency"
Get-ClusterResource | Get-ClusterResourceDependency | Format-Table Resource, DependencyExpression -AutoSize
"== Get-ClusterResourceType"
Get-ClusterResourceType 'SQL Server Availability Group' | Format-List Name, DllName
"== Get-Service"
Get-Service MSSQLSERVER, SQLSERVERAGENT, ClusSvc | Format-Table Name, Status, StartType -AutoSize
