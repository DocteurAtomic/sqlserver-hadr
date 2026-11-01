# ci: skip (Windows cluster of the course, not the containers)
# Runs on each node of the cluster, in an elevated PowerShell, before the demos of module 8:
# makes the virtual disk C:\m08\m08-disk.vhdx, formatted and mounted as M:, with a folder
# M:\data for the files of m08_registrations. The disk is 300 MB on SQL01 and 100 MB on SQL02:
# clip 8.4 fills the secondary first. Then run 00-setup-cluster.sql on SQL01.
# Usage: .\00-setup-cluster.ps1 -SizeMB 300     (on SQL01; -SizeMB 100 on SQL02)
param([int]$SizeMB = 300)
$ProgressPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force C:\m08 | Out-Null
@"
create vdisk file=C:\m08\m08-disk.vhdx maximum=$SizeMB type=expandable
attach vdisk
create partition primary
format fs=ntfs quick label=M08
assign letter=M
"@ | Set-Content C:\m08\diskpart.txt -Encoding ascii
diskpart /s C:\m08\diskpart.txt | Select-String 'successfully'
New-Item -ItemType Directory -Force M:\data | Out-Null
Get-Volume -DriveLetter M | Format-Table DriveLetter, FileSystemLabel, Size, SizeRemaining -AutoSize
