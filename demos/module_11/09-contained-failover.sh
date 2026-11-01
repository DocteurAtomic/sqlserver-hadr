#!/usr/bin/env bash
# Clip 11.3: the planned failover of the contained group, every database resumed. Whichever of
# hadrlab1 and hadrlab2 is the secondary of m11_contained becomes its primary, by
# setup/ag-failover.sh (module 6), which resumes each copy the failover suspends, the two
# databases of the group among them. Then: the login m11_shop connects to the new primary, and
# at the next minute the job runs there, and there only; the history of the job, in msdb of the
# group, says which instance ran each time. Appends the duration of the failover to
# evidence/module_11.md. Leaves the new primary in place. Run after 07-contained.sh (and
# 08-contained-half-resumed.sh, if played).
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
shop() {
    $engine exec -i -e SQLCMDPASSWORD='M11-Shop-2026!' "$1" /opt/mssql-tools18/bin/sqlcmd \
        -S 127.0.0.1 -U m11_shop -C -b -h -1 -W -d m11_signup \
        -Q "SET NOCOUNT ON; SELECT CONCAT(N'  connected to ', @@SERVERNAME, N' as ', SUSER_SNAME(), N', database ', DB_NAME(),
            N', ', CONVERT(nvarchar(20), DATABASEPROPERTYEX(DB_NAME(), 'Updateability')));" 2>&1 \
        | grep -v '^ *$' | sed 's/^Sqlcmd: Error: Microsoft ODBC Driver 18 for SQL Server : /  /' || true
}
role() {
    sql $1 -h -1 -Q "SET NOCOUNT ON; SELECT rs.role_desc FROM sys.dm_hadr_availability_replica_states AS rs
        JOIN sys.availability_groups AS g ON g.group_id = rs.group_id WHERE g.name = N'm11_contained' AND rs.is_local = 1;" | tr -d '[:space:]'
}
if [ "$(role hadrlab1)" = PRIMARY ]; then target=hadrlab2; else target=hadrlab1; fi
echo "== the planned failover of m11_contained to $target"
out=$(bash setup/ag-failover.sh m11_contained $target)
echo "$out" | sed 's/^/  /'
took=$(echo "$out" | tail -1 | grep -o '[0-9.]* s$' | cut -d' ' -f1)
echo
echo "== m11_shop, on $target"
shop $target
echo
echo "== the next minute (at most 90 seconds)"
before=$(sql $target -h -1 -d m11_signup -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.JobRun WHERE written_on = N'$target';" | tr -d '[:space:]')
for i in $(seq 1 90); do
    now=$(sql $target -h -1 -d m11_signup -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.JobRun WHERE written_on = N'$target';" | tr -d '[:space:]')
    [ "$now" -gt "$before" ] && break
    sleep 1
done
echo "  $(date -u +%T) UTC"
sql $target -d m11_signup -Q "SET NOCOUNT ON; SELECT written_on, COUNT(*) AS runs, MAX(written_at) AS last_run FROM dbo.JobRun GROUP BY written_on ORDER BY written_on;"
[ "$now" -gt "$before" ] || { echo "the job has not run on $target within 90 seconds" >&2; exit 1; }
echo
echo "== $target, msdb of the group: the history of the job"
sql $target -d m11_contained_master -Q "SET NOCOUNT ON; SELECT h.server, COUNT(*) AS runs,
    SUM(IIF(h.run_status = 1, 1, 0)) AS succeeded, MAX(msdb.dbo.agent_datetime(h.run_date, h.run_time)) AS last_run
FROM msdb.dbo.sysjobhistory AS h JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'm11_signup_heartbeat' AND h.step_id = 0 GROUP BY h.server ORDER BY h.server;"
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 11, planned failover of the contained group m11_contained (two replicas, three databases) to $target: $took s; the login and the job of the group there at once, the job running on the new primary at the next minute; three containers on one host" >> evidence/module_11.md
