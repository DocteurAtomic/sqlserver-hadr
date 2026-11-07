#!/usr/bin/env bash
# Clip 12.2: the AlwaysOn_health session. The groups of the lab are created in T-SQL, without
# the SSMS wizard: the session exists on each instance (Learn: created with the group), but it
# does not run and does not start with the instance (startup_state 0), and it has written no
# file. What the disconnection of clip 12.1 left is therefore only in the error log: read on
# hadrlab1 and hadrlab3 since m12_registration was created there (00-setup.sh, the seeding on
# hadrlab3), the lines that name the other instance or the endpoint, the DebugTraceVarArgs
# traces of the HADR layer left out. Then the session started on the three instances and set
# to start with them, and a first incident it records: the copy of hadrlab2 suspended, then
# resumed. 99-cleanup.sh stops the session again, sets it back as it was, and deletes its files.
# Run after 02-disconnected.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
session_state() {
    sql $1 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  ', @@SERVERNAME, N': AlwaysOn_health ', IIF(x.name IS NULL, N'stopped', N'running'),
              N', startup_state ', s.startup_state,
              N', ', (SELECT COUNT(*) FROM sys.dm_os_enumerate_filesystem(N'/var/opt/mssql/log', N'AlwaysOn_health*.xel')),
              N' file(s)')
FROM sys.server_event_sessions AS s LEFT JOIN sys.dm_xe_sessions AS x ON x.name = s.name
WHERE s.name = N'AlwaysOn_health';"
}
echo "== the session, on each instance"
for n in $nodes; do session_state $n; done
echo
for n in hadrlab1 hadrlab3; do
    other=$([ $n = hadrlab1 ] && echo hadrlab3 || echo hadrlab1)
    echo "== $n: the error log since m12_registration was created there, the lines about $other and the endpoint"
    sql $n -h -1 -v OTHER="$other" <<'SQL'
SET NOCOUNT ON;
DECLARE @l TABLE (logdate datetime, process nvarchar(50), txt nvarchar(4000));
INSERT @l EXEC sys.xp_readerrorlog 0, 1;
SELECT CONCAT(N'  ', CONVERT(char(12), logdate, 114), N' ', LEFT(txt, 150))
FROM @l
WHERE logdate >= (SELECT create_date FROM sys.databases WHERE name = N'm12_registration')
  AND txt NOT LIKE N'%DebugTraceVarArgs%'
  AND (txt LIKE N'%''$(OTHER)''%' OR txt LIKE N'%Database Mirroring endpoint%')
ORDER BY logdate;
SQL
    echo
done
echo "== the session started on the three instances, STARTUP_STATE = ON"
for n in $nodes; do
    sql $n -h -1 -Q "SET NOCOUNT ON;
IF NOT EXISTS (SELECT * FROM sys.dm_xe_sessions WHERE name = N'AlwaysOn_health')
    ALTER EVENT SESSION AlwaysOn_health ON SERVER STATE = START;
ALTER EVENT SESSION AlwaysOn_health ON SERVER WITH (STARTUP_STATE = ON);"
    session_state $n
done
echo
echo "== hadrlab2: SET HADR SUSPEND, then SET HADR RESUME ($(date -u +%T) UTC)"
sql hadrlab2 -Q "ALTER DATABASE m12_registration SET HADR SUSPEND;"
sleep 2
resume_copy hadrlab2 m12_registration
wait_ag_database hadrlab1 AgPacha m12_registration 60 hadrlab2 | sed 's/^/  /'
