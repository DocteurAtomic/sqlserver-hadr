#!/usr/bin/env bash
# Clip 11.2: the job on every replica, with the guard of the primary. The job is defined once, in
# the script below, and created the same way on hadrlab1, hadrlab2 and hadrlab3 (an existing one
# is dropped first). Its first step runs in master, and asks sys.fn_hadr_is_primary_replica
# whether this instance holds the primary replica of m11_registration: when not (0, or NULL if
# the database is not in a group), it raises an error, and the step's failure action quits the
# job reporting success. Only then does the second step, in m11_registration, write. Started on
# the three instances: three successes, one row, written by the primary. Then a planned failover
# to hadrlab1, the three started again: one more row, written by hadrlab1. Leaves hadrlab1
# primary. Run after 05-job-on-secondary.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
create_job() {
    sql $1 -h -1 <<'SQL'
SET NOCOUNT ON;
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'm11_heartbeat')
    EXEC msdb.dbo.sp_delete_job @job_name = N'm11_heartbeat', @delete_history = 0;
EXEC msdb.dbo.sp_add_job @job_name = N'm11_heartbeat', @owner_login_name = N'sa',
    @description = N'Module 11: writes the instance it runs on into m11_registration.dbo.Heartbeat, on the primary only';
-- Step 1, in master: a secondary cannot open m11_registration, the step would fail there.
-- on_fail_action 1: quit the job reporting success; on_success_action 3: go to the next step.
EXEC msdb.dbo.sp_add_jobstep @job_name = N'm11_heartbeat', @step_id = 1, @step_name = N'primary only',
    @subsystem = N'TSQL', @database_name = N'master',
    @command = N'IF sys.fn_hadr_is_primary_replica(N''m11_registration'') IS DISTINCT FROM 1
    RAISERROR(N''Not the primary replica of m11_registration: nothing to do'', 16, 1);',
    @on_success_action = 3, @on_fail_action = 1;
EXEC msdb.dbo.sp_add_jobstep @job_name = N'm11_heartbeat', @step_id = 2, @step_name = N'heartbeat',
    @subsystem = N'TSQL', @database_name = N'm11_registration',
    @command = N'INSERT dbo.Heartbeat DEFAULT VALUES;';
EXEC msdb.dbo.sp_add_jobserver @job_name = N'm11_heartbeat', @server_name = N'(local)';
PRINT CONCAT(N'  ', @@SERVERNAME, N': m11_heartbeat created, two steps');
SQL
}
round() {  # starts the job on the three instances, prints its last history on each
    for n in $nodes; do
        run_job $n m11_heartbeat 60 | grep -v 'started successfully' | sed 's/^/  /'
        sql $n -h -1 -Q "SET NOCOUNT ON; SELECT TOP (1) CONCAT(N'    last step: ', h.step_id, N' ', h.step_name, N', ',
            IIF(h.run_status = 1, N'succeeded', N'failed'), IIF(h.run_status = 1, N'', N': ' + LEFT(STUFF(h.message, 1, CHARINDEX(N'. ', h.message) + 1, N''), 100)))
            FROM msdb.dbo.sysjobhistory AS h JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
            WHERE j.name = N'm11_heartbeat' AND h.step_id > 0 ORDER BY h.instance_id DESC;"
    done
}
heartbeats() {
    sql $1 -Q "SET NOCOUNT ON; SELECT written_on, COUNT(*) AS heartbeats, MAX(written_at) AS last_one
FROM m11_registration.dbo.Heartbeat GROUP BY written_on ORDER BY written_on;"
}
echo "== the same job, created on the three instances"
for n in $nodes; do create_job $n; done
echo
echo "== hadrlab2 is the primary: the job started on the three"
round
heartbeats hadrlab2
echo
echo "== the planned failover of AgPacha to hadrlab1"
bash setup/ag-failover.sh AgPacha hadrlab1 | tail -1 | sed 's/^/  /'
echo
echo "== hadrlab1 is the primary: the job started on the three"
round
heartbeats hadrlab1
