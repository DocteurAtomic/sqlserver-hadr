# ci: skip (Windows cluster of the course, not the containers)
# Runs on a node of the cluster, in an elevated PowerShell. Module 9, clip 9.1: what the
# cluster manages on this availability group cluster, and what a failover cluster instance
# would add (a SQL Server resource, its Agent, a shared disk). Reads only.
# Usage: .\02-cluster-resources.ps1, on SQL01 then on SQL02 (the services part is local)
$ProgressPreference = 'SilentlyContinue'
'== Get-ClusterGroup'
Get-ClusterGroup | Format-Table Name, OwnerNode, State -AutoSize
'== Get-ClusterResource'
Get-ClusterResource | Sort-Object OwnerGroup, Name |
    Format-Table Name, ResourceType, OwnerGroup, OwnerNode, State -AutoSize
'== Resource types for SQL Server'
Get-ClusterResourceType | Where-Object Name -like 'SQL*' | Format-Table Name, DllName -AutoSize
'== Disks: cluster disks, cluster shared volumes, disks the cluster could take'
"Physical Disk resources: $(@(Get-ClusterResource | Where-Object ResourceType -eq 'Physical Disk').Count)"
"Cluster shared volumes:  $(@(Get-ClusterSharedVolume).Count)"
"Available disks:         $(@(Get-ClusterAvailableDisk -ErrorAction SilentlyContinue).Count)"
'== The SQL Server services of this node'
Get-CimInstance Win32_Service -Filter "Name='MSSQLSERVER' OR Name='SQLSERVERAGENT'" |
    Format-Table Name, State, StartMode -AutoSize
