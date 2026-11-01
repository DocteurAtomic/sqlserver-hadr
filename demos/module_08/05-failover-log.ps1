# ci: skip (Windows cluster of the course, not the containers)
# Runs on a node of the cluster. Module 8, clips 8.2 and 8.3: generates the cluster log of a
# node for the last minutes (times in UTC) and keeps the lines that tell how the cluster
# handled a failure of the role Pacha: the health check of the resource DLL (hadrag), the
# restart on the same node, the failover decision and the move to the other node.
# Usage: .\05-failover-log.ps1 -Node SQL01 -Minutes 5 [-From '12:17:20' -To '12:17:40']
param([string]$Node = $env:COMPUTERNAME, [int]$Minutes = 5, [string]$From = '00:00:00', [string]$To = '23:59:59')
$ProgressPreference = 'SilentlyContinue'
$dir = 'C:\m08\log'
New-Item -ItemType Directory -Force $dir | Out-Null
$file = Get-ClusterLog -Node $Node -Destination $dir -TimeSpan $Minutes
"== $($file.Name), $From to $To UTC"
$patterns = 'service is not alive', 'IsAlive has indicated failure', 'is not healthy', 'health state',
    'Will queue immediate restart', 'Online for resource Pacha failed', 'is causing group Pacha to failover',
    'Not failing over group', 'RcmGroup::Failover', 'RcmGroup::Move: \(Pacha', 'Pacha, Pending --> Online',
    'Pacha, Online --> Pending', 'Pacha, Pending --> Failed', 'Lease timeout', 'failure condition level',
    'database .* is not online', 'Res Pacha: OnlinePending -> Online'
Get-Content $file.FullName | ForEach-Object { $_ -replace '^[0-9a-f]{8}\.[0-9a-f]{8}::', '' } |
    Where-Object { $_ -match '^\d{4}/\d\d/\d\d-(\d\d:\d\d:\d\d)' -and $Matches[1] -ge $From -and $Matches[1] -le $To } |
    Select-String -Pattern $patterns | ForEach-Object { $_.Line }
