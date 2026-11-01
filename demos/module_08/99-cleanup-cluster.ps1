# ci: skip (Windows cluster of the course, not the containers)
# Runs on each node of the cluster, in an elevated PowerShell, after 99-cleanup-cluster.sql:
# puts back the failover threshold of the role Pacha (4294967295, the default: n - 1 failures
# in six hours) when clip 8.2 raised it, detaches the virtual disk M: and deletes C:\m08.
# Usage: .\99-cleanup-cluster.ps1
$ProgressPreference = 'SilentlyContinue'
$g = Get-ClusterGroup Pacha
$g.FailoverThreshold = 4294967295
'FailoverThreshold {0}' -f (Get-ClusterGroup Pacha).FailoverThreshold
@"
select vdisk file=C:\m08\m08-disk.vhdx
detach vdisk
"@ | Set-Content C:\m08\detach.txt -Encoding ascii
diskpart /s C:\m08\detach.txt | Select-String 'successfully'
Remove-Item C:\m08 -Recurse -Force
'C:\m08 left: {0}' -f (Test-Path C:\m08)
