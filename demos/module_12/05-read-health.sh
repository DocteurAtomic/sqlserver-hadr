#!/usr/bin/env bash
# Clip 12.2: reads what AlwaysOn_health recorded on each of the three instances, during the last
# minutes (5 by default, or the first argument). The session writes its buffers to its files
# every 30 seconds at most (MAX_DISPATCH_LATENCY), so the script waits 31 seconds first. One
# line per event, the debug traces (hadr_trace_message) and the connection setups without error
# left out: the time (UTC), the event,
# and what matters in it (the error number and its message, the statement of a DDL, the
# previous and current state of a replica, the synchronization state of a copy seen by the
# primary). Run after 04-restart.sh, or after
# 03-health-session.sh (the CI, which skips 04): it then shows the suspend and the resume.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
minutes=${1:-5}
sleep 31
for n in $nodes; do
    echo "== $n: AlwaysOn_health, the last $minutes minutes"
    sql $n -h -1 -v MINUTES="$minutes" <<'SQL'
SET NOCOUNT ON;
WITH e AS (
    SELECT CAST(event_data AS xml) AS x
    FROM sys.fn_xe_file_target_read_file(N'/var/opt/mssql/log/AlwaysOn_health*.xel', NULL, NULL, NULL)
    WHERE object_name <> N'hadr_trace_message'),
f AS (
    SELECT x.value(N'(event/@timestamp)[1]', N'datetime2(3)') AS t,
           x.value(N'(event/@name)[1]', N'sysname') AS name,
           x.value(N'(event/data[@name="error_number"]/value)[1]', N'int') AS error_number,
           x.value(N'(event/data[@name="message"]/value)[1]', N'nvarchar(400)') AS message,
           x.value(N'(event/data[@name="statement"]/value)[1]', N'nvarchar(200)') AS statement,
           x.value(N'(event/data[@name="ddl_phase"]/text)[1]', N'sysname') AS phase,
           x.value(N'(event/data[@name="availability_group_name"]/value)[1]', N'sysname') AS ag,
           x.value(N'(event/data[@name="previous_state"]/text)[1]', N'sysname') AS previous_state,
           x.value(N'(event/data[@name="current_state"]/text)[1]', N'sysname') AS current_state,
           x.value(N'(event/data[@name="sync_state"]/text)[1]', N'sysname') AS sync_state,
           x.value(N'(event/data[@name="commit_policy"]/text)[1]', N'sysname') AS commit_policy,
           x.value(N'(event/data[@name="replica_id"]/value)[1]', N'uniqueidentifier') AS replica_id,
           x.value(N'(event/data[@name="database_id"]/value)[1]', N'int') AS database_id,
           x.value(N'(event/data[@name="setup_event"]/text)[1]', N'sysname') AS setup_event,
           x.value(N'(event/data[@name="error_message"]/value)[1]', N'nvarchar(200)') AS error_message,
           x.value(N'(event/data[@name="address"]/value)[1]', N'nvarchar(100)') AS address
    FROM e)
SELECT CONCAT(N'  ', CONVERT(char(12), t, 114), N' ', name, N' ',
              CASE WHEN name = N'ucs_connection_setup' THEN CONCAT(address, N' ', setup_event, N': ', LEFT(error_message, 80))
                   WHEN error_number IS NOT NULL THEN CONCAT(error_number, N' ', LEFT(message, 110))
                   WHEN statement IS NOT NULL THEN CONCAT(phase, N': ', LEFT(REPLACE(REPLACE(statement, NCHAR(13), N''), NCHAR(10), N' '), 110))
                   WHEN current_state IS NOT NULL THEN CONCAT(ag, N' ', previous_state, N' -> ', current_state)
                   WHEN sync_state IS NOT NULL THEN CONCAT(DB_NAME(database_id), N' toward ',
                        ISNULL(ar.replica_server_name, N'?'), N': ', sync_state, N', commit policy ', commit_policy)
                   ELSE N'' END)
FROM f LEFT JOIN sys.availability_replicas AS ar ON ar.replica_id = f.replica_id
WHERE t >= DATEADD(minute, -$(MINUTES), SYSUTCDATETIME())
  -- the connection setups that went well, several per connection, are left out
  AND NOT (name = N'ucs_connection_setup' AND ISNULL(error_number, 0) = 0)
ORDER BY t;
SQL
    echo
done
