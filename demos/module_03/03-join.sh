#!/usr/bin/env bash
# Clip 3.2: hadrlab2, then hadrlab3, join AgPacha and allow it to create its databases
# (GRANT CREATE ANY DATABASE), which starts the automatic seeding of PachadataTraining from
# hadrlab1. Each join is followed by a wait, at most five minutes, until that copy is caught
# up (wait_ag_database, setup/lib.sh). Then what the seeding did, read on hadrlab1, and what
# it left in msdb on hadrlab2. Appends the seeding durations and sizes to
# evidence/module_03.md. Run after 02-create-ag.sql.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
# The seeding statistics keep every seeding since the instance started: only this one is read.
t0=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(varchar(23), SYSUTCDATETIME(), 121);" | tr -d '\r')
echo "Before the joins, PachadataTraining on the secondaries:"
for n in hadrlab2 hadrlab3; do
    sql $n -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(@@SERVERNAME, ': ',
        ISNULL((SELECT state_desc FROM sys.databases WHERE name = N'PachadataTraining'), 'no database'));"
done
for n in hadrlab2 hadrlab3; do
    echo
    echo "$n joins AgPacha:"
    t=$(date +%s.%N)
    sql $n <<'SQL'
SET NOCOUNT ON;
ALTER AVAILABILITY GROUP AgPacha JOIN WITH (CLUSTER_TYPE = NONE);
ALTER AVAILABILITY GROUP AgPacha GRANT CREATE ANY DATABASE;
SQL
    echo "JOIN and GRANT in $(awk -v s=$t -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }') s"
    wait_ag_database hadrlab1 AgPacha PachadataTraining 300 $n
done
echo
echo "hadrlab1, what the seeding did:"
sql hadrlab1 -v T0="$t0" <<'SQL'
SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, s.current_state, s.number_of_attempts AS attempts,
       FORMAT(DATEDIFF(millisecond, s.start_time, s.completion_time) / 1000.0, N'0.0') AS seconds
FROM sys.dm_hadr_automatic_seeding AS s
JOIN sys.availability_replicas AS ar ON ar.replica_id = s.ag_remote_replica_id
ORDER BY s.start_time;
SELECT REPLACE(REPLACE(remote_machine_name, N'tcp://', N''), N':5022', N'') AS replica,
       role_desc AS role, internal_state_desc AS state,
       transferred_size_bytes / 1048576 AS transferred_mb, database_size_bytes / 1048576 AS files_mb,
       transfer_rate_bytes_per_second / 1048576 AS mb_per_s, is_compression_enabled AS compressed
FROM sys.dm_hadr_physical_seeding_stats
WHERE local_database_name = N'PachadataTraining' AND start_time_utc >= '$(T0)'
ORDER BY start_time_utc;
SQL
echo
echo "hadrlab2, msdb after the seeding:"
sql hadrlab2 <<'SQL'
SET NOCOUNT ON;
SELECT b.type, b.is_copy_only, b.server_name, m.physical_device_name AS device,
       CONVERT(varchar(19), b.backup_start_date, 120) AS backup_start
FROM msdb.dbo.backupset AS b JOIN msdb.dbo.backupmediafamily AS m ON m.media_set_id = b.media_set_id
WHERE b.database_name = N'PachadataTraining';
SELECT restore_type, CONVERT(varchar(19), restore_date, 120) AS restore_date
FROM msdb.dbo.restorehistory WHERE destination_database_name = N'PachadataTraining';
SQL
line=$(sql hadrlab1 -h -1 -v T0="$t0" -Q "SET NOCOUNT ON;
SELECT STRING_AGG(CONCAT(REPLACE(REPLACE(p.remote_machine_name, N'tcp://', N''), N':5022', N''), N' ',
           FORMAT(DATEDIFF(millisecond, p.start_time_utc, p.end_time_utc) / 1000.0, N'0.0'), N' s for ',
           p.transferred_size_bytes / 1048576, N' MB'), N', ')
FROM sys.dm_hadr_physical_seeding_stats AS p WHERE p.internal_state_desc = N'Success'
  AND p.local_database_name = N'PachadataTraining' AND p.start_time_utc >= '\$(T0)';")
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 3, automatic seeding of PachadataTraining from hadrlab1 into AgPacha (one secondary after the other, no compression, three containers on one host): $line" >> evidence/module_03.md
