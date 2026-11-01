# ci: skip (Windows cluster of the course, not the containers)
# Runs on the secondary replica (SQL02). Module 8, clip 8.4: freezes the SQL Server process for
# a number of seconds, then thaws it. A frozen process neither answers nor closes its
# connections: this is the secondary that no longer responds, which a clean stop does not
# show. The node, its cluster service and its vote are not touched.
# Usage: .\10-freeze.ps1 -Seconds 30
param([int]$Seconds = 30)
$ProgressPreference = 'SilentlyContinue'
Add-Type -Name Nt -Namespace M08 -MemberDefinition @'
[DllImport("ntdll.dll")] public static extern int NtSuspendProcess(IntPtr handle);
[DllImport("ntdll.dll")] public static extern int NtResumeProcess(IntPtr handle);
'@
$p = Get-Process sqlservr
'{0} freeze sqlservr ({1})' -f (Get-Date).ToUniversalTime().ToString('HH:mm:ss.f'), [M08.Nt]::NtSuspendProcess($p.Handle)
Start-Sleep -Seconds $Seconds
'{0} thaw sqlservr ({1})' -f (Get-Date).ToUniversalTime().ToString('HH:mm:ss.f'), [M08.Nt]::NtResumeProcess($p.Handle)
