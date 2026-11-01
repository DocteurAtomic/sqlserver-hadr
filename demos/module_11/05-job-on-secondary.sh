#!/usr/bin/env bash
# Clip 11.2: the job after the failover. AgPacha has moved to hadrlab2 (04-copy-with-sid.sh), and
# the job m11_heartbeat exists on hadrlab1 only, where 00-setup.sh created it. Started on
# hadrlab1, now a secondary, it fails: its step runs in m11_registration, which a secondary that
# is not readable does not open. Started on hadrlab2, the primary, it does not exist (Msg 14262).
# The rows of dbo.Heartbeat, read on the primary, say where the job ran. Leaves hadrlab2
# primary. Run after 04-copy-with-sid.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
jobs() {  # the job m11_heartbeat on each instance: its steps
    for n in $nodes; do
        sql $n -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'  ', @@SERVERNAME, N': ',
            ISNULL((SELECT CONCAT(N'm11_heartbeat, ', COUNT(*), N' step(s): ', STRING_AGG(CONCAT(s.step_id, N' ', s.step_name,
                    N' in ', s.database_name), N', ') WITHIN GROUP (ORDER BY s.step_id))
                    FROM msdb.dbo.sysjobs AS j JOIN msdb.dbo.sysjobsteps AS s ON s.job_id = j.job_id
                    WHERE j.name = N'm11_heartbeat' GROUP BY j.job_id), N'no job m11_heartbeat'));"
    done
}
echo "== the job m11_heartbeat, on each instance"
jobs
echo
echo "== hadrlab1, now a secondary: the job started"
run_job hadrlab1 m11_heartbeat 60 2>&1 | grep -v 'started successfully' | sed 's/^/  /' || true
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT TOP (1) CONCAT(N'  history, step ', h.step_id, N': ', h.message)
FROM msdb.dbo.sysjobhistory AS h JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'm11_heartbeat' AND h.step_id = 1 ORDER BY h.instance_id DESC;"
echo
echo "== hadrlab2, the primary: the job started"
sql hadrlab2 -Q "EXEC msdb.dbo.sp_start_job @job_name = N'm11_heartbeat';" 2>&1 | sed 's/^/  /' || true
echo
echo "== hadrlab2: where the job has written"
sql hadrlab2 -Q "SET NOCOUNT ON; SELECT written_on, COUNT(*) AS heartbeats, MAX(written_at) AS last_one
FROM m11_registration.dbo.Heartbeat GROUP BY written_on ORDER BY written_on;"
