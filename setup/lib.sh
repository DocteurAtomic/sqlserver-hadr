# Sourced by the scripts of setup/, demos/ and exercises/: the container engine, and sql(),
# which runs sqlcmd inside an instance's container, password taken from the container
# environment (SQLCMDPASSWORD, set by compose.yaml), never written on the command line.
# Usage, from a script:  . "$(dirname "$0")/../../setup/lib.sh"   then   sql hadrlab2 < file.sql
engine=${ENGINE:-docker}
nodes="hadrlab1 hadrlab2 hadrlab3"
# Git Bash on Windows rewrites /var/opt/... arguments without this; no effect elsewhere.
export MSYS_NO_PATHCONV=1
sql() {  # instance, then sqlcmd arguments
    local c=$1; shift
    $engine exec -i "$c" /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U sa -C -b -I -W "$@"
}
# Runs a SQL Server Agent job and waits for it to finish, at most a number of seconds (120 by
# default); exits with 1 when the job fails or does not finish in time. When the job is already
# running, it waits for that run to finish first; when the schedule starts it at the same
# moment, it waits for that run instead of starting another. Prints one line: the job, its
# outcome, its duration. Added by module 2 for the log shipping jobs.
# Usage:  run_job hadrlab2 LSCopy_m02_registration [seconds]
run_job() {
    local c=$1 job=$2 limit=${3:-120}
    sql "$c" -h -1 -v JOB="$job" LIMIT="$limit" <<'SQL'
SET NOCOUNT ON;
DECLARE @job sysname = N'$(JOB)', @limit int = $(LIMIT), @t0 datetime = GETDATE();
DECLARE @id uniqueidentifier = (SELECT job_id FROM msdb.dbo.sysjobs WHERE name = @job);
DECLARE @session int = (SELECT MAX(session_id) FROM msdb.dbo.syssessions);
IF @id IS NULL
BEGIN
    RAISERROR(N'run_job: the job %s does not exist on %s', 16, 1, @job, @@SERVERNAME);
    RETURN;
END;
-- A run already going (started by its schedule) finishes first.
WHILE EXISTS (SELECT * FROM msdb.dbo.sysjobactivity
              WHERE job_id = @id AND session_id = @session
                AND start_execution_date IS NOT NULL AND stop_execution_date IS NULL)
      AND DATEDIFF(second, @t0, GETDATE()) < @limit
    WAITFOR DELAY '00:00:01';
SET @t0 = GETDATE();
BEGIN TRY
    EXEC msdb.dbo.sp_start_job @job_id = @id;
END TRY
BEGIN CATCH
    -- 22022: the schedule started it in the same second; that run is the one we wait for.
    IF ERROR_NUMBER() <> 22022 THROW;
END CATCH;
WHILE NOT EXISTS (SELECT * FROM msdb.dbo.sysjobactivity
                  WHERE job_id = @id AND session_id = @session
                    AND start_execution_date >= DATEADD(second, -1, @t0)
                    AND stop_execution_date IS NOT NULL)
      AND DATEDIFF(second, @t0, GETDATE()) < @limit
    WAITFOR DELAY '00:00:01';
DECLARE @status int, @start datetime, @stop datetime;
SELECT @status = h.run_status, @start = a.start_execution_date, @stop = a.stop_execution_date
FROM msdb.dbo.sysjobactivity AS a
LEFT JOIN msdb.dbo.sysjobhistory AS h ON h.instance_id = a.job_history_id
WHERE a.job_id = @id AND a.session_id = @session
  AND a.start_execution_date >= DATEADD(second, -1, @t0) AND a.stop_execution_date IS NOT NULL;
IF @stop IS NULL
BEGIN
    RAISERROR(N'run_job: %s did not finish on %s within %d seconds', 16, 1, @job, @@SERVERNAME, @limit);
    RETURN;
END;
PRINT CONCAT(@job, N' on ', @@SERVERNAME, N': ',
             CASE @status WHEN 1 THEN N'succeeded' ELSE N'FAILED' END,
             N' in ', DATEDIFF(second, @start, @stop), N' s');
IF @status <> 1
    RAISERROR(N'run_job: %s failed on %s: read its history (msdb.dbo.sysjobhistory)', 16, 1, @job, @@SERVERNAME);
SQL
}
# Disables a SQL Server Agent job, then waits for a run already going to finish, at most 60
# seconds: after it returns, the job does not start again. Added by module 2.
# Usage:  disable_job hadrlab1 LSBackup_m02_registration
disable_job() {
    local c=$1 job=$2
    sql "$c" -h -1 -v JOB="$job" <<'SQL'
SET NOCOUNT ON;
DECLARE @job sysname = N'$(JOB)', @t0 datetime = GETDATE();
EXEC msdb.dbo.sp_update_job @job_name = @job, @enabled = 0;
WHILE EXISTS (SELECT * FROM msdb.dbo.sysjobactivity AS a JOIN msdb.dbo.sysjobs AS j ON j.job_id = a.job_id
              WHERE j.name = @job AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
                AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL)
      AND DATEDIFF(second, @t0, GETDATE()) < 60
    WAITFOR DELAY '00:00:01';
IF DATEDIFF(second, @t0, GETDATE()) >= 60
    RAISERROR(N'disable_job: %s still running on %s after 60 seconds', 16, 1, @job, @@SERVERNAME);
PRINT CONCAT(@job, N' on ', @@SERVERNAME, N': disabled');
SQL
}
# Waits until a database of an availability group is caught up on every secondary replica,
# read on the primary, at most a number of seconds (300 by default): no automatic seeding
# still going, SYNCHRONIZED on the synchronous replicas, SYNCHRONIZING or SYNCHRONIZED on the
# asynchronous ones. Exits with 1
# when the automatic seeding of a replica fails, or when the time runs out, and says which
# replica is missing. A fifth argument limits the wait to one secondary. Prints one line:
# the database, the time waited. Added by module 3.
# Usage:  wait_ag_database hadrlab1 AgPacha PachadataTraining [seconds] [replica]
wait_ag_database() {
    local c=$1 ag=$2 db=$3 limit=${4:-300} only=${5:-*}
    sql "$c" -h -1 -v AG="$ag" DB="$db" LIMIT="$limit" ONLY="$only" <<'SQL'
SET NOCOUNT ON;
DECLARE @ag sysname = N'$(AG)', @db sysname = N'$(DB)', @limit int = $(LIMIT), @only sysname = N'$(ONLY)',
        @t0 datetime2(3) = SYSDATETIME(), @missing nvarchar(400), @failed nvarchar(400),
        @checkpoint nvarchar(300);
SET @checkpoint = N'USE ' + QUOTENAME(@db) + N'; CHECKPOINT;';
WHILE 1 = 1
BEGIN
    -- The secondary replicas whose copy of the database is not caught up yet.
    SELECT @missing = STRING_AGG(CONCAT(ar.replica_server_name, N' (',
               ISNULL(drs.synchronization_state_desc, N'not joined'), N')'), N', ')
    FROM sys.availability_groups AS g
    JOIN sys.availability_replicas AS ar ON ar.group_id = g.group_id
    LEFT JOIN sys.dm_hadr_database_replica_states AS drs
           ON drs.replica_id = ar.replica_id AND drs.database_id = DB_ID(@db)
    WHERE g.name = @ag AND ar.replica_server_name <> @@SERVERNAME
      AND (@only = N'*' OR ar.replica_server_name = @only)
      AND (NOT (drs.synchronization_state_desc = N'SYNCHRONIZED'
                OR (ar.availability_mode_desc = N'ASYNCHRONOUS_COMMIT'
                    AND drs.synchronization_state_desc = N'SYNCHRONIZING'))
           -- An asynchronous copy says SYNCHRONIZING before its seeding has finished.
           OR EXISTS (SELECT * FROM sys.dm_hadr_automatic_seeding AS s
                      JOIN sys.availability_databases_cluster AS adc ON adc.group_database_id = s.ag_db_id
                      WHERE adc.database_name = @db AND s.ag_remote_replica_id = ar.replica_id
                        AND s.current_state NOT IN (N'COMPLETED', N'FAILED')));
    -- A seeding of this database that failed since the wait began.
    SELECT @failed = STRING_AGG(CONCAT(ar.replica_server_name, N': ', s.failure_state_desc), N', ')
    FROM sys.dm_hadr_automatic_seeding AS s
    JOIN sys.availability_replicas AS ar ON ar.replica_id = s.ag_remote_replica_id
    JOIN sys.availability_databases_cluster AS adc ON adc.group_database_id = s.ag_db_id
    WHERE adc.database_name = @db AND s.current_state = N'FAILED'
      AND (@only = N'*' OR ar.replica_server_name = @only) AND s.start_time >= DATEADD(second, -5, @t0);
    IF @missing IS NULL OR @failed IS NOT NULL OR DATEDIFF(second, @t0, SYSDATETIME()) >= @limit BREAK;
    -- The seeding of an asynchronous replica stays in CATCHUP until the primary writes new log:
    -- a checkpoint writes some.
    EXEC (@checkpoint);
    WAITFOR DELAY '00:00:01';
END;
IF @failed IS NOT NULL
    RAISERROR(N'wait_ag_database: the seeding of %s failed on %s', 16, 1, @db, @failed);
ELSE IF @missing IS NOT NULL
    RAISERROR(N'wait_ag_database: %s not caught up within %d seconds on %s', 16, 1, @db, @limit, @missing);
ELSE
    PRINT CONCAT(@db, N' in ', @ag, N': ', IIF(@only = N'*', N'every secondary', @only), N' caught up, after ',
                 FORMAT(DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0, N'0.0'), N' s');
SQL
}
# Opens one connection from inside the lab network, with the sqlcmd of a container (the names
# hadrlab1 to hadrlab3, and a listener, only resolve there: a client on the host would be
# redirected to a name it cannot resolve), and prints where it landed: the instance, the
# database and its updateability, or the error the connection got. Added by module 5.
# Usage:  lands_on <from container> <server> [sqlcmd options]
#   e.g.  lands_on hadrlab3 hadrlab1 -d m05_reports -K ReadOnly
lands_on() {
    local from=$1 server=$2; shift 2
    $engine exec -i "$from" /opt/mssql-tools18/bin/sqlcmd -C -l 10 -S "$server" -U sa -h -1 -W "$@" \
        -Q "SET NOCOUNT ON; SELECT CONCAT(@@SERVERNAME, N' ', DB_NAME(), N' ', CONVERT(nvarchar(20), DATABASEPROPERTYEX(DB_NAME(), 'Updateability')))" 2>&1 \
        | grep -v '^ *$' | tail -1 | sed 's/^Sqlcmd: Error: Microsoft ODBC Driver 18 for SQL Server : //'
    return 0
}
