#!/usr/bin/env bash
# Clip 11.3: the contained availability group, without a cluster. On hadrlab1, the database
# m11_signup (full recovery, full backup), then the group m11_contained, WITH (CLUSTER_TYPE =
# NONE, CONTAINED), hadrlab1 and hadrlab2 in synchronous commit, automatic seeding (hadrlab3 is
# not in it); hadrlab2 joins (join_ag). SQL Server adds two databases to the group,
# m11_contained_master and m11_contained_msdb; the script waits until the three are caught up.
# Then, connected with m11_contained_master as initial database (the context of the group), the
# login m11_shop (password M11-Shop-2026!), its user in m11_signup, and the job
# m11_signup_heartbeat, every minute, which writes the instance it runs on into dbo.JobRun.
# What each context sees, on each replica; m11_shop connecting; the first run of the job (at
# most 75 seconds); and what the context of the group refuses. Leaves hadrlab1 primary of
# m11_contained. Runs next to AgPacha, which it does not touch. Run after 06-job-guard.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
shop() {  # connects as m11_shop, with its password; the remaining arguments go to sqlcmd
    $engine exec -i -e SQLCMDPASSWORD='M11-Shop-2026!' "$1" /opt/mssql-tools18/bin/sqlcmd \
        -S 127.0.0.1 -U m11_shop -C -b -h -1 -W "${@:2}" \
        -Q "SET NOCOUNT ON; SELECT CONCAT(N'  connected to ', @@SERVERNAME, N' as ', SUSER_SNAME(), N', database ', DB_NAME(),
            N', ', CONVERT(nvarchar(20), DATABASEPROPERTYEX(DB_NAME(), 'Updateability')));" 2>&1 \
        | grep -v '^ *$' | sed 's/^Sqlcmd: Error: Microsoft ODBC Driver 18 for SQL Server : /  /' || true
}
echo "== hadrlab1: m11_signup, then the group m11_contained"
t0=$(date +%s.%N)
(sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
CREATE DATABASE m11_signup;
ALTER DATABASE m11_signup SET RECOVERY FULL;
GO
CREATE TABLE m11_signup.dbo.JobRun (
    id int IDENTITY PRIMARY KEY,
    written_on sysname NOT NULL DEFAULT @@SERVERNAME,
    written_at datetime2(0) NOT NULL DEFAULT SYSDATETIME());
BACKUP DATABASE m11_signup TO DISK = N'/var/opt/mssql/share/m11/m11_signup-full.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
GO
CREATE AVAILABILITY GROUP m11_contained
WITH (CLUSTER_TYPE = NONE, CONTAINED)
FOR DATABASE m11_signup
REPLICA ON
    N'hadrlab1' WITH (ENDPOINT_URL = N'tcp://hadrlab1:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
                      FAILOVER_MODE = MANUAL, SEEDING_MODE = AUTOMATIC),
    N'hadrlab2' WITH (ENDPOINT_URL = N'tcp://hadrlab2:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
                      FAILOVER_MODE = MANUAL, SEEDING_MODE = AUTOMATIC);
SQL
) | { grep -v '^Processed \|^BACKUP DATABASE successfully' || true; }
join_ag hadrlab2 m11_contained
for db in m11_signup m11_contained_master m11_contained_msdb; do
    wait_ag_database hadrlab1 m11_contained $db 300 | sed 's/^/  /'
done
echo "  created and caught up in $(awk -v s=$t0 -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }') s"
sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT DB_NAME(d.database_id) AS db, ar.replica_server_name AS replica, d.synchronization_state_desc AS sync
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
JOIN sys.availability_groups AS g ON g.group_id = d.group_id
WHERE g.name = N'm11_contained' ORDER BY db, replica;"
echo
echo "== hadrlab1, in the context of the group: the login, its user, the job"
sql hadrlab1 -d m11_contained_master -h -1 <<'SQL' | { grep -v 'Changed database' || true; }
SET NOCOUNT ON;
SELECT CONCAT(N'  DB_NAME() ', DB_NAME(), N', DB_ID() ', DB_ID(), N', contained_availability_group_id ',
              (SELECT contained_availability_group_id FROM sys.dm_exec_sessions WHERE session_id = @@SPID));
CREATE LOGIN m11_shop WITH PASSWORD = N'M11-Shop-2026!', CHECK_POLICY = OFF, DEFAULT_DATABASE = m11_signup;
GO
USE m11_signup;
CREATE USER m11_shop FOR LOGIN m11_shop;
ALTER ROLE db_datareader ADD MEMBER m11_shop;
GO
EXEC msdb.dbo.sp_add_job @job_name = N'm11_signup_heartbeat', @owner_login_name = N'sa',
    @description = N'Module 11: writes the instance it runs on into m11_signup.dbo.JobRun';
EXEC msdb.dbo.sp_add_jobstep @job_name = N'm11_signup_heartbeat', @step_name = N'heartbeat',
    @subsystem = N'TSQL', @database_name = N'm11_signup', @command = N'INSERT dbo.JobRun DEFAULT VALUES;';
EXEC msdb.dbo.sp_add_jobschedule @job_name = N'm11_signup_heartbeat', @name = N'm11_every_minute',
    @freq_type = 4, @freq_interval = 1, @freq_subday_type = 4, @freq_subday_interval = 1;
EXEC msdb.dbo.sp_add_jobserver @job_name = N'm11_signup_heartbeat', @server_name = N'(local)';
SQL
echo
echo "== what each context sees, on each replica"
printf '  %-9s %-9s %-14s %-9s %s\n' instance context "login m11_shop" job databases
for n in hadrlab1 hadrlab2; do
    for ctx in master m11_contained_master; do
        sql $n -d $ctx -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'  ', @@SERVERNAME, N'  ',
            IIF((SELECT contained_availability_group_id FROM sys.dm_exec_sessions WHERE session_id = @@SPID) IS NULL, N'instance ', N'group    '), N' ',
            (SELECT COUNT(*) FROM sys.server_principals WHERE name = N'm11_shop'), N'              ',
            (SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name = N'm11_signup_heartbeat'), N'         ',
            (SELECT STRING_AGG(name, N', ') WITHIN GROUP (ORDER BY database_id) FROM sys.databases WHERE name <> N'tempdb'));"
    done
done
echo
echo "== m11_shop, on hadrlab1: without a database, then in m11_signup"
shop hadrlab1
shop hadrlab1 -d m11_signup
echo
echo "== the first run of the job (at most 75 seconds)"
for i in $(seq 1 75); do
    r=$(sql hadrlab1 -h -1 -d m11_signup -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.JobRun;" | tr -d '[:space:]')
    [ "${r:-0}" -gt 0 ] && break
    sleep 1
done
sql hadrlab1 -d m11_signup -Q "SET NOCOUNT ON; SELECT written_on, COUNT(*) AS runs, MAX(written_at) AS last_run FROM dbo.JobRun GROUP BY written_on;"
[ "${r:-0}" -gt 0 ] || { echo "the job has not run within 75 seconds" >&2; exit 1; }
echo
echo "== hadrlab1, in the context of the group: what is refused"
sql hadrlab1 -d m11_contained_master -Q "ALTER AVAILABILITY GROUP m11_contained SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0);" 2>&1 | sed 's/^/  /' || true
# The value set is the one in use: on an instance context, the statement would change nothing.
sql hadrlab1 -d m11_contained_master -Q "DECLARE @v int = (SELECT CAST(value_in_use AS int) FROM sys.configurations WHERE name = N'show advanced options');
EXEC sp_configure 'show advanced options', @v;" 2>&1 | sed 's/^/  /' || true
sql hadrlab1 -d m11_contained_master -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'  login m11_app of the instance, seen from the group: ', COUNT(*)) FROM sys.server_principals WHERE name = N'm11_app';"
