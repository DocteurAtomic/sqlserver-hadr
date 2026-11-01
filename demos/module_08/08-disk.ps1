# ci: skip (Windows cluster of the course, not the containers)
# Runs on the node whose disk M: must disappear or come back. Module 8, clip 8.3: M: is a
# virtual disk (C:\m08\m08-disk.vhdx, made by 00-setup-cluster.ps1) that holds the files of
# m08_registrations; taking it offline is what a lost SAN volume looks like to SQL Server.
# Usage: .\08-disk.ps1 -Offline   or   .\08-disk.ps1 -Online
param([switch]$Offline, [switch]$Online)
$ProgressPreference = 'SilentlyContinue'
$disk = Get-Disk | Where-Object Location -like '*\m08-disk.vhdx'
if ($Offline) { Set-Disk -Number $disk.Number -IsOffline $true }
if ($Online) { Set-Disk -Number $disk.Number -IsOffline $false }
'{0} disk {1} {2}' -f (Get-Date).ToUniversalTime().ToString('HH:mm:ss.f'), $disk.Number,
    (Get-Disk -Number $disk.Number).OperationalStatus
