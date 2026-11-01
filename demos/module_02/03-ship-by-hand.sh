#!/usr/bin/env bash
# Clip 2.2: one cycle of log shipping, job by job. Writes a batch of 25 registrations on
# hadrlab1, then runs the three jobs in their order, each one to its end (run_job, at most
# two minutes each): the log backup on hadrlab1, the copy and the restore on hadrlab2. The
# batch is then readable on hadrlab2, which stays read-only between two restores (STANDBY).
# Shows the files on the way and what the jobs wrote in the log shipping history.
# Run after 02-secondary.sql. The schedules keep running: run_job waits for a run already going.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
count='SET NOCOUNT ON; SELECT CONCAT(@@SERVERNAME, '"'"': '"'"', COUNT(*), '"'"' rows of m02 batch 1'"'"')
       FROM m02_registration.Enrollment.Enrollment WHERE OrderReference = '"'"'m02 batch 1'"'"';'
echo "hadrlab1, a batch of registrations:"
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; EXEC m02_registration.dbo.m02_register 25, 'm02 batch 1';"
sql hadrlab1 -h -1 -Q "$count"
echo
echo "The three jobs, in order:"
t=$(date +%s.%N)
run_job hadrlab1 LSBackup_m02_registration
run_job hadrlab2 LSCopy_m02_registration
run_job hadrlab2 LSRestore_m02_registration
echo "one cycle in $(awk -v s=$t -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }') s"
echo
echo "hadrlab2, the copy:"
sql hadrlab2 -h -1 -Q "$count"
sql hadrlab2 <<'SQL'
SET NOCOUNT ON;
SELECT name, state_desc AS state, is_in_standby, is_read_only
FROM sys.databases WHERE name = N'm02_registration';
GO
-- The copy is read-only between two restores (error 3906 expected).
BEGIN TRY
    EXEC m02_registration.dbo.m02_register 1, 'm02 on hadrlab2';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
GO
SQL
echo
echo "The log backups on the shared volume, then the copies on the disk of hadrlab2, and the undo file of STANDBY:"
$engine exec hadrlab2 sh -c 'ls -l /var/opt/mssql/share/logship/m02_registration | tail -3;
    ls -l /var/opt/mssql/logship-copy/m02_registration | tail -3; ls -l /var/opt/mssql/data/*.tuf'
echo
echo "What the last cycle wrote in the log shipping history (msdb.dbo.log_shipping_monitor_history_detail):"
for n in hadrlab1 hadrlab2; do
    sql $n -h -1 -s '|' <<'SQL'
SET NOCOUNT ON;
-- The last session of each job of this instance (0 backup, 1 copy, 2 restore). The copy rows
-- have no database_name: the jobs are found by their agent_id.
WITH last AS (
    SELECT agent_type, MAX(session_id) AS session_id
    FROM msdb.dbo.log_shipping_monitor_history_detail
    WHERE agent_id IN (SELECT primary_id FROM msdb.dbo.log_shipping_primary_databases
                   WHERE primary_database = N'm02_registration'
                   UNION ALL SELECT secondary_id FROM msdb.dbo.log_shipping_secondary
                   WHERE primary_database = N'm02_registration')
    GROUP BY agent_type)
SELECT @@SERVERNAME,
       CHOOSE(h.agent_type + 1, 'backup', 'copy', 'restore'),
       CONVERT(varchar(12), h.log_time, 114),
       -- The folders shortened, for the screen.
       LEFT(REPLACE(REPLACE(h.message, N'/var/opt/mssql/share/logship/m02_registration', N'<share>'),
                    N'/var/opt/mssql/logship-copy/m02_registration', N'<copy>'), 150)
FROM msdb.dbo.log_shipping_monitor_history_detail AS h
JOIN last ON last.agent_type = h.agent_type AND last.session_id = h.session_id
WHERE (h.message LIKE N'Backing up%' OR h.message LIKE N'Copying log backup file to%'
       OR h.message LIKE N'Restored log%' OR h.message LIKE N'%operation was successful%'
       OR h.message LIKE N'Skipping%')
ORDER BY h.log_time;
SQL
done
