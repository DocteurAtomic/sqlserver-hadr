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
# Joins a secondary to a group created on the primary and lets it create the databases. A
# group of the same name dropped a moment before can still be leaving the instance: the JOIN
# then fails with Msg 41180 ("the availability group is being dropped"), which the first
# Docker run of the CI met in module 4, right after the cleanup of module 3. The JOIN is
# tried again every 2 seconds on that error only, for 60 seconds at most.
# Usage:  join_ag hadrlab2 AgPacha
join_ag() {
    local c=$1 ag=$2 out i
    for i in $(seq 1 30); do
        if out=$(sql "$c" -h -1 2>&1 <<SQL
SET NOCOUNT ON;
ALTER AVAILABILITY GROUP $ag JOIN WITH (CLUSTER_TYPE = NONE);
ALTER AVAILABILITY GROUP $ag GRANT CREATE ANY DATABASE;
SQL
        ); then
            [ -z "$out" ] || echo "$out"
            return 0
        fi
        case $out in
            *"Msg 41180,"*) sleep 2 ;;
            *) echo "$out" >&2; return 1 ;;
        esac
    done
    echo "$out" >&2
    return 1
}
# Runs a SQL Server Agent job and waits for it to finish, at most a number of seconds (120 by
# default); exits with 1 when the job fails or does not finish in time. When the job is already
# running, it waits for that run to finish first; when the schedule starts it at the same
# moment, it waits for that run instead of starting another. Prints one line: the job, its
# outcome, its duration. Added by module 2 for the log shipping jobs.
# Usage:  run_job hadrlab2 LSCopy_m02_registration [seconds]
run_job() {
    # sp_start_job sends its error 22022 (the schedule started the job in the same second)
    # from an extended procedure, which TRY...CATCH does not catch: sqlcmd prints it as
    # "HResult 0x5606" and, with -b, exits with 1 although the run waited for has succeeded.
    # Seen once in the CI. That case alone is turned back into a success, and the two lines
    # of the message are dropped.
    local out rc
    if out=$(_run_job "$@" 2>&1); then rc=0; else rc=$?; fi
    if [ $rc -ne 0 ] && printf '%s\n' "$out" | grep -q '^HResult 0x5606,' \
       && ! printf '%s\n' "$out" | grep -E '^(Msg|HResult) ' | grep -vq '^HResult 0x5606,' \
       && printf '%s\n' "$out" | grep -q ': succeeded in '; then
        rc=0
    fi
    printf '%s\n' "$out" | grep -v -e '^HResult 0x5606,' -e 'refused because the job is already running' || true
    return $rc
}
_run_job() {
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
# asynchronous ones. A fifth argument limits the wait to one secondary. Prints one line: the
# database, the time waited. Exits with 1 when the time runs out, and says which replica is
# missing, after a report of the seedings of the database (seeding_report). Added by module 3.
# An automatic seeding can stop for good: on a slow CI runner, the connection between the
# endpoints timed out while two seedings ran at once, the restore of m04_registration on
# hadrlab2 finished, its join to the group failed (Msg 35250, "the connection to the primary
# replica is not active"), and SQL Server never tried again, leaving a copy in RESTORING
# outside the group. Such a copy (not caught up, the last seeding of it finished more than 30
# seconds ago, no seeding of it going on) is seeded again by reseed_copy, twice at most.
# Usage:  wait_ag_database hadrlab1 AgPacha PachadataTraining [seconds] [replica]
wait_ag_database() {
    local c=$1 ag=$2 db=$3 limit=${4:-300} only=${5:-*} t0=$SECONDS out left r stuck reseeds=0
    while :; do
        left=$(( limit - (SECONDS - t0) ))
        [ "$left" -gt 0 ] || left=1
        if out=$(_wait_ag_database "$c" "$ag" "$db" "$left" "$only" 2>&1); then
            echo "$out"
            return 0
        fi
        stuck=$(printf '%s\n' "$out" | sed -n 's/^stuck: //p')
        if [ -z "$stuck" ] || [ "$reseeds" -ge 2 ]; then
            seeding_report "$c" "$db" >&2
            echo "$out" | grep -v '^stuck: ' >&2
            return 1
        fi
        reseeds=$((reseeds + 1))
        seeding_report "$c" "$db" >&2
        for r in $stuck; do
            reseed_copy "$r" "$ag" "$db" >&2 || return 1
        done
    done
}
_wait_ag_database() {
    local c=$1 ag=$2 db=$3 limit=$4 only=$5
    sql "$c" -h -1 -v AG="$ag" DB="$db" LIMIT="$limit" ONLY="$only" <<'SQL'
SET NOCOUNT ON;
DECLARE @ag sysname = N'$(AG)', @db sysname = N'$(DB)', @limit int = $(LIMIT), @only sysname = N'$(ONLY)',
        @t0 datetime2(3) = SYSDATETIME(), @missing nvarchar(400), @stuck nvarchar(400),
        @stuck_since datetime2(3), @checkpoint nvarchar(300);
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
    -- The copies whose automatic seeding stopped: not synchronizing, the last seeding of them
    -- finished more than 30 seconds ago (SQL Server retries a transient failure by itself
    -- within that time), none going on, and so for 20 seconds in a row (a database just added
    -- to the group can show an old seeding as its last one, until its own begins).
    SELECT @stuck = STRING_AGG(ar.replica_server_name, N' ')
    FROM sys.availability_groups AS g
    JOIN sys.availability_replicas AS ar ON ar.group_id = g.group_id
    LEFT JOIN sys.dm_hadr_database_replica_states AS drs
           ON drs.replica_id = ar.replica_id AND drs.database_id = DB_ID(@db)
    CROSS APPLY (SELECT TOP (1) s.current_state, ISNULL(s.completion_time, s.start_time) AS ended
                 FROM sys.dm_hadr_automatic_seeding AS s
                 JOIN sys.availability_databases_cluster AS adc ON adc.group_database_id = s.ag_db_id
                 WHERE adc.database_name = @db AND s.ag_remote_replica_id = ar.replica_id
                 ORDER BY s.start_time DESC) AS last_seeding
    WHERE g.name = @ag AND ar.replica_server_name <> @@SERVERNAME
      AND (@only = N'*' OR ar.replica_server_name = @only)
      AND ar.seeding_mode_desc = N'AUTOMATIC'
      AND ISNULL(drs.synchronization_state_desc, N'NOT SYNCHRONIZING') = N'NOT SYNCHRONIZING'
      AND last_seeding.current_state IN (N'COMPLETED', N'FAILED')
      AND last_seeding.ended < DATEADD(second, -30, GETDATE());
    SET @stuck_since = IIF(@stuck IS NULL, NULL, ISNULL(@stuck_since, SYSDATETIME()));
    IF @missing IS NULL OR DATEDIFF(second, @stuck_since, SYSDATETIME()) >= 20
       OR DATEDIFF(second, @t0, SYSDATETIME()) >= @limit BREAK;
    -- The seeding of an asynchronous replica stays in CATCHUP until the primary writes new log:
    -- a checkpoint writes some.
    EXEC (@checkpoint);
    WAITFOR DELAY '00:00:01';
END;
IF @missing IS NOT NULL AND DATEDIFF(second, @stuck_since, SYSDATETIME()) >= 20
BEGIN
    PRINT CONCAT(N'stuck: ', @stuck);
    RAISERROR(N'wait_ag_database: the seeding of %s stopped on %s', 16, 1, @db, @stuck);
END
ELSE IF @missing IS NOT NULL
    RAISERROR(N'wait_ag_database: %s not caught up within %d seconds on %s', 16, 1, @db, @limit, @missing);
ELSE
    PRINT CONCAT(@db, N' in ', @ag, N': ', IIF(@only = N'*', N'every secondary', @only), N' caught up, after ',
                 FORMAT(DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0, N'0.0'), N' s');
SQL
}
# Seeds again the copy of a database on a secondary whose automatic seeding stopped: drops the
# copy when it is in RESTORING outside the group, then grants the group CREATE ANY DATABASE
# again, which starts a new seeding. Leaves alone a copy that is joined, or whose seeding is
# going on. Prints one line. Called by wait_ag_database.
# Usage:  reseed_copy hadrlab2 AgPacha m04_registration
reseed_copy() {
    local c=$1 ag=$2 db=$3
    sql "$c" -h -1 -v AG="$ag" DB="$db" <<'SQL'
SET NOCOUNT ON;
DECLARE @db sysname = N'$(DB)';
IF EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states WHERE database_id = DB_ID(@db) AND is_local = 1)
    PRINT CONCAT(N'reseed_copy: ', @db, N' on ', @@SERVERNAME, N' is joined, left alone');
ELSE IF EXISTS (SELECT * FROM sys.dm_hadr_automatic_seeding AS s
                JOIN sys.availability_databases_cluster AS adc ON adc.group_database_id = s.ag_db_id
                WHERE adc.database_name = @db AND s.current_state NOT IN (N'COMPLETED', N'FAILED'))
    PRINT CONCAT(N'reseed_copy: ', @db, N' on ', @@SERVERNAME, N' is being seeded, left alone');
ELSE
BEGIN
    IF DB_ID(@db) IS NOT NULL AND DATABASEPROPERTYEX(@db, 'Status') <> N'RESTORING'
        THROW 50000, N'reseed_copy: the copy is neither joined nor in RESTORING', 1;
    IF DB_ID(@db) IS NOT NULL
        EXEC (N'DROP DATABASE ' + QUOTENAME(@db));
    ALTER AVAILABILITY GROUP $(AG) GRANT CREATE ANY DATABASE;
    PRINT CONCAT(N'reseed_copy: ', @db, N' on ', @@SERVERNAME, N': copy dropped, seeding started again');
END;
SQL
}
# Prints what the instances say of the automatic seedings of a database: on the primary given,
# the last seedings of it per replica (sys.dm_hadr_automatic_seeding), then, on each instance,
# the physical seedings (sys.dm_hadr_physical_seeding_stats) with their failure. Added after
# the CI met a seeding that failed with "SQL Error" and no error code.
# Usage:  seeding_report hadrlab1 m04_registration
seeding_report() {
    local c=$1 db=$2 n
    echo "== seedings of $db, read on $c"
    sql "$c" -h -1 -s '|' -v DB="$db" <<'SQL' || true
SET NOCOUNT ON;
SELECT TOP (6) CONVERT(varchar(23), s.start_time, 121), ar.replica_server_name, s.current_state,
       s.failure_state_desc, s.error_code, s.number_of_attempts
FROM sys.dm_hadr_automatic_seeding AS s
JOIN sys.availability_databases_cluster AS adc ON adc.group_database_id = s.ag_db_id
JOIN sys.availability_replicas AS ar ON ar.replica_id = s.ag_remote_replica_id
WHERE adc.database_name = N'$(DB)'
ORDER BY s.start_time DESC;
SQL
    for n in $nodes; do
        sql "$n" -h -1 -s '|' -v DB="$db" <<'SQL' || true
SET NOCOUNT ON;
SELECT TOP (3) @@SERVERNAME, role_desc, internal_state_desc, CONVERT(varchar(19), start_time_utc, 120),
       transferred_size_bytes / 1048576, failure_code, failure_message
FROM sys.dm_hadr_physical_seeding_stats
WHERE local_database_name = N'$(DB)'
ORDER BY start_time_utc DESC;
SQL
    done
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
