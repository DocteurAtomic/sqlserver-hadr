# ci: skip (Windows cluster of the course, not the containers)
# Runs on a node of the cluster. Module 7, clip 7.3: generates the cluster log of a node for
# the last minutes (times in UTC), keeps the lines that tell a node loss, then reads the same
# minutes in the SQL Server error log (times in the local time of the server). -ErrorLog is
# the number of the error log file: 0 for the current one, 1 for the one before the last
# restart of the instance, and so on.
# Usage: .\05-cluster-log.ps1 -Node SQL01 -Minutes 40 -From '2026-11-01 02:53:00' -To '2026-11-01 02:58:00' -ErrorLog 1
param([string]$Node = $env:COMPUTERNAME, [int]$Minutes = 30, [string]$From, [string]$To, [int]$ErrorLog = 0)
$ProgressPreference = 'SilentlyContinue'
$dir = 'C:\m07\log'
New-Item -ItemType Directory -Force $dir | Out-Null
$file = Get-ClusterLog -Node $Node -Destination $dir -TimeSpan $Minutes
"== $($file.Name), lines of a node loss"
Select-String -Path $file.FullName -Pattern 'Missed 40% of the heart beats', 'Lost connection to node', 'Lost quorum', 'One off quorum', 'quorum resource owner', 'death timer', 'Terminating resource', 'Issuing Arbitrate', 'File Share Witness. in clustered role .Cluster Group. has transitioned' |
    Where-Object Line -notmatch '^\[' | ForEach-Object { $_.Line -replace '^[0-9a-f]{8}\.[0-9a-f]{8}::', '' }
if ($From) {
    "== SQL Server error log $ErrorLog, $From to $To"
    $q = "SET NOCOUNT ON; EXEC xp_readerrorlog $ErrorLog, 1, NULL, NULL, '$From', '$To';"
    sqlcmd -S . -E -C -W -h -1 -s '|' -Q $q | Select-String -Pattern 'connection timeout', 'lost quorum', 'RESOLVING_NORMAL', 'PRIMARY_NORMAL', 'listener network name', 'virtual network name', 'is online' |
        ForEach-Object { $_.Line }
}
