# ci: skip (Windows cluster of the course, not the containers)
# Runs on the node to update, in an elevated PowerShell, only while its replica of Pacha is
# SECONDARY: it refuses to run on the primary. Module 10, clip 10.4: one node of the rolling
# update. Downloads the update package, checks its SHA-256 against the one published in the
# KB article, installs it on every instance of the node, then prints the version before and
# after and the time each step took. -DownloadOnly stops after the check (the package stays
# in C:\Windows\Temp until a run without it). -RestartOnly installs nothing and restarts the
# SQL Server service and its Agent: the same interruption of the replica as the setup, for a
# rehearsal when no newer update exists.
# Usage, with the values of the KB article and of the Microsoft Update Catalog:
#   .\13-update-node.ps1 -Url https://catalog.s.download.windowsupdate.com/.../sqlserver2025-kb5125471-x64_....exe `
#                        -Sha256 EBDC3024C76023CE599D3FDF3174A1FC8FF2958EE7009A7655274CE263644B85
#   .\13-update-node.ps1 -RestartOnly
param([string]$Url, [string]$Sha256, [switch]$DownloadOnly, [switch]$RestartOnly)
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
function Now { (Get-Date).ToUniversalTime().ToString('HH:mm:ss') }
function Version { (sqlcmd -S . -E -C -h -1 -W -Q "SET NOCOUNT ON; SELECT CONCAT(@@SERVERNAME, ' ', CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(20)), ' ', CAST(SERVERPROPERTY('ProductUpdateLevel') AS nvarchar(20)), ' ', CAST(SERVERPROPERTY('ProductUpdateReference') AS nvarchar(20)))" | Out-String).Trim() }
$role = (sqlcmd -S . -E -C -h -1 -W -Q "SET NOCOUNT ON; SELECT role_desc FROM sys.dm_hadr_availability_replica_states WHERE is_local = 1" | Out-String).Trim()
if ($role -ne 'SECONDARY') { throw "The local replica is '$role', not SECONDARY: fail Pacha over to the other node first." }
"{0} before: {1}" -f (Now), (Version)
$t0 = Get-Date
if ($RestartOnly) {
    Restart-Service MSSQLSERVER -Force
    Start-Service SQLSERVERAGENT
    "{0} service restarted in {1:0.0} s" -f (Now), ((Get-Date) - $t0).TotalSeconds
} else {
    if (-not $Url -or -not $Sha256) { throw 'Give -Url and -Sha256, or -RestartOnly.' }
    $exe = Join-Path $env:windir ('Temp\' + ($Url -split '/')[-1])
    if (-not (Test-Path $exe)) { Invoke-WebRequest -Uri $Url -OutFile $exe -UseBasicParsing }
    $hash = (Get-FileHash $exe -Algorithm SHA256).Hash
    "{0} {1}, {2:0} MB, downloaded in {3:0} s, SHA-256 {4}" -f (Now), (Split-Path $exe -Leaf),
        ((Get-Item $exe).Length / 1MB), ((Get-Date) - $t0).TotalSeconds, $hash
    if ($hash -ne $Sha256.ToUpper()) { Remove-Item $exe; throw 'SHA-256 mismatch: package deleted, nothing installed.' }
    if ($DownloadOnly) { "{0} SHA-256 matches the KB article; nothing installed" -f (Now); return }
    $t1 = Get-Date
    $p = Start-Process $exe -ArgumentList '/q', '/IAcceptSQLServerLicenseTerms', '/Action=Patch', '/AllInstances' -Wait -PassThru
    "{0} setup exit code {1}, in {2:0} s" -f (Now), $p.ExitCode, ((Get-Date) - $t1).TotalSeconds
    Remove-Item $exe
    if ($p.ExitCode -ne 0) { throw "Setup failed: read C:\Program Files\Microsoft SQL Server\170\Setup Bootstrap\Log\Summary.txt" }
}
"{0} after: {1}" -f (Now), (Version)
