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
