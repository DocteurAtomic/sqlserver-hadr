#!/usr/bin/env bash
# Exercise of module 11, a solution. Run after 1-start.sh, AgObjects primary on hadrlab2.
#   1. The login: on hadrlab1, where ex_app was created, the statement that recreates it is built
#      from sys.sql_logins, password hash and SID included (what sp_help_revlogin or
#      Copy-DbaLogin do), and run on hadrlab2.
#   2. The job: one definition, created the same way on hadrlab1 and hadrlab2 (the old one
#      dropped first). Its first step, in master, quits reporting success when
#      sys.fn_hadr_is_primary_replica('ex_objects') is not 1; the second, in ex_objects, writes.
# Other solutions hold too: check.sh reads the state.
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
stmt=$(sql hadrlab1 -h -1 <<'SQL' | tr -d '\r' | grep -v '^ *$'
SET NOCOUNT ON;
DECLARE @s nvarchar(max);
SELECT @s = CONCAT(N'CREATE LOGIN ', QUOTENAME(name),
    N' WITH PASSWORD = ', CONVERT(nvarchar(max), CAST(LOGINPROPERTY(name, 'PasswordHash') AS varbinary(256)), 1),
    N' HASHED, SID = ', CONVERT(nvarchar(max), sid, 1),
    N', DEFAULT_DATABASE = ', QUOTENAME(default_database_name),
    N', CHECK_POLICY = ', IIF(is_policy_checked = 1, N'ON', N'OFF'),
    N', CHECK_EXPIRATION = ', IIF(is_expiration_checked = 1, N'ON', N'OFF'), N';')
FROM sys.sql_logins WHERE name = N'ex_app';
PRINT @s;
SQL
)
[ -n "$stmt" ] || { echo "no login ex_app on hadrlab1: run exercises/module_11/1-start.sh" >&2; exit 1; }
sql hadrlab2 -Q "IF SUSER_ID(N'ex_app') IS NOT NULL DROP LOGIN ex_app; $stmt"
for n in hadrlab1 hadrlab2; do
    sql $n -h -1 <<'SQL'
SET NOCOUNT ON;
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'ex_heartbeat')
    EXEC msdb.dbo.sp_delete_job @job_name = N'ex_heartbeat', @delete_history = 0;
EXEC msdb.dbo.sp_add_job @job_name = N'ex_heartbeat', @owner_login_name = N'sa',
    @description = N'Exercise of module 11: writes the instance it runs on into ex_objects.dbo.Heartbeat, on the primary only';
EXEC msdb.dbo.sp_add_jobstep @job_name = N'ex_heartbeat', @step_id = 1, @step_name = N'primary only',
    @subsystem = N'TSQL', @database_name = N'master',
    @command = N'IF sys.fn_hadr_is_primary_replica(N''ex_objects'') IS DISTINCT FROM 1
    RAISERROR(N''Not the primary replica of ex_objects: nothing to do'', 16, 1);',
    @on_success_action = 3, @on_fail_action = 1;
EXEC msdb.dbo.sp_add_jobstep @job_name = N'ex_heartbeat', @step_id = 2, @step_name = N'heartbeat',
    @subsystem = N'TSQL', @database_name = N'ex_objects', @command = N'INSERT dbo.Heartbeat DEFAULT VALUES;';
EXEC msdb.dbo.sp_add_jobserver @job_name = N'ex_heartbeat', @server_name = N'(local)';
PRINT CONCAT(@@SERVERNAME, N': ex_heartbeat created, with the guard of the primary');
SQL
done
