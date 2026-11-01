# ci: skip (Windows cluster of the course, not the containers)
# Runs on a node of the cluster, in an elevated PowerShell. Module 8, clip 8.1: the listener
# of the availability group Pacha as the cluster sees it (a network name and an IP address in
# the role Pacha, with their parameters), as DNS answers it, and as SQL Server describes it.
# Usage: .\01-listener.ps1
$ProgressPreference = 'SilentlyContinue'
'== Get-ClusterResource, role Pacha'
Get-ClusterGroup Pacha | Get-ClusterResource | Format-Table Name, ResourceType, OwnerNode, State -AutoSize
'== The network name'
Get-ClusterResource Pacha_PachaSQL | Get-ClusterParameter DnsName, HostRecordTTL, RegisterAllProvidersIP |
    Format-Table Name, Value -AutoSize
'== The IP address'
Get-ClusterResource Pacha_192.168.200.31 | Get-ClusterParameter Address, SubnetMask, Network |
    Format-Table Name, Value -AutoSize
'== Resolve-DnsName PachaSQL'
Resolve-DnsName PachaSQL | Format-Table Name, IPAddress, TTL -AutoSize
'== SQL Server'
sqlcmd -S . -E -C -W -Q @"
SET NOCOUNT ON;
SELECT l.dns_name, l.port, ip.ip_address, ip.ip_subnet_mask, ip.state_desc
FROM sys.availability_group_listeners AS l
JOIN sys.availability_group_listener_ip_addresses AS ip ON ip.listener_id = l.listener_id;
SELECT ip_address, port, type_desc, state_desc FROM sys.dm_tcp_listener_states WHERE type_desc = 'TSQL';
"@
