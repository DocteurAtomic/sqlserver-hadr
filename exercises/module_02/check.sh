#!/usr/bin/env bash
# Exercise of module 2: checks the log shipping of ex_logship from hadrlab1 to hadrlab3, and
# the planned failover that ends it. It reads the state, never a script: on hadrlab1, the
# primary configuration with hadrlab3 as its secondary, its backup job disabled after the
# failover, the database left RESTORING by the tail backup; on hadrlab3, the secondary
# configuration in STANDBY, its jobs disabled after the failover, a log backup taken after
# the row 'probe' and restored in STANDBY by the jobs, the monitor that saw a restore, the
# database online and writable, the tail of hadrlab1 restored (same last LSN: no row lost),
# and a row 'after failover'. Exits with 0 when everything holds, with 1 otherwise.
# Usage: ./exercises/module_02/check.sh     (with Podman: ENGINE=podman ...)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
fail=0
primary=$(sql hadrlab1 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
DECLARE @r TABLE (n int IDENTITY, line nvarchar(400));
DECLARE @pid uniqueidentifier, @job uniqueidentifier;
SELECT @pid = primary_id, @job = backup_job_id
FROM msdb.dbo.log_shipping_primary_databases WHERE primary_database = N'ex_logship';
INSERT @r SELECT IIF(DB_ID(N'ex_logship') IS NOT NULL, N'ok   hadrlab1: ex_logship exists',
    N'FAIL hadrlab1: ex_logship is missing: run exercises/module_02/1-start.sh');
INSERT @r SELECT IIF(@pid IS NOT NULL, N'ok   hadrlab1: ex_logship is a log shipping primary',
    N'FAIL hadrlab1: ex_logship is not a log shipping primary (sp_add_log_shipping_primary_database)');
INSERT @r SELECT IIF(EXISTS (SELECT * FROM msdb.dbo.log_shipping_primary_secondaries
                             WHERE primary_id = @pid AND UPPER(secondary_server) = N'HADRLAB3'
                               AND secondary_database = N'ex_logship'),
    N'ok   hadrlab1: hadrlab3 is its secondary',
    N'FAIL hadrlab1: hadrlab3 is not declared as its secondary (sp_add_log_shipping_primary_secondary)');
INSERT @r SELECT CASE
    WHEN NOT EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE job_id = @job)
        THEN N'FAIL hadrlab1: the backup job of ex_logship is missing'
    WHEN EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE job_id = @job AND enabled = 1)
        THEN N'FAIL hadrlab1: the backup job of ex_logship is still enabled: disable it at the failover'
    ELSE N'ok   hadrlab1: the backup job exists, disabled since the failover' END;
INSERT @r SELECT IIF(DATABASEPROPERTYEX(N'ex_logship', 'Status') = N'RESTORING',
    N'ok   hadrlab1: ex_logship is RESTORING (tail of the log backed up WITH NORECOVERY)',
    CONCAT(N'FAIL hadrlab1: ex_logship is ', ISNULL(CAST(DATABASEPROPERTYEX(N'ex_logship', 'Status') AS nvarchar(20)), N'missing'),
           N', not RESTORING: back up the tail of its log WITH NORECOVERY'));
SELECT line FROM @r ORDER BY n;
-- The last LSN of the last log backup of ex_logship taken here: the tail.
SELECT CONCAT(N'LSN ', ISNULL(CAST((SELECT TOP 1 last_lsn FROM msdb.dbo.backupset
    WHERE database_name = N'ex_logship' AND type = 'L' AND server_name = @@SERVERNAME
    ORDER BY backup_finish_date DESC, backup_set_id DESC) AS varchar(30)), N'none'));
SQL
)
rc=$?
if [ $rc -ne 0 ] || [ -z "$primary" ]; then echo "$primary" | head -3; echo "FAIL hadrlab1 does not answer"; exit 1; fi
echo "$primary" | grep -v '^LSN '
lsn=$(echo "$primary" | sed -n 's/^LSN //p' | tr -d '[:space:]')
secondary=$(sql hadrlab3 -h -1 -v LSN="$lsn" <<'SQL' 2>&1
SET NOCOUNT ON;
DECLARE @r TABLE (n int IDENTITY, line nvarchar(400));
DECLARE @sid uniqueidentifier, @copy uniqueidentifier, @restore uniqueidentifier, @mode bit;
SELECT @sid = d.secondary_id, @mode = d.restore_mode, @copy = s.copy_job_id, @restore = s.restore_job_id
FROM msdb.dbo.log_shipping_secondary_databases AS d
JOIN msdb.dbo.log_shipping_secondary AS s ON s.secondary_id = d.secondary_id
WHERE d.secondary_database = N'ex_logship' AND UPPER(s.primary_server) = N'HADRLAB1'
  AND s.primary_database = N'ex_logship';
INSERT @r SELECT IIF(@sid IS NOT NULL, N'ok   hadrlab3: ex_logship is the log shipping secondary of hadrlab1',
    N'FAIL hadrlab3: ex_logship is not a log shipping secondary of hadrlab1 (sp_add_log_shipping_secondary_primary, then _secondary_database)');
INSERT @r SELECT IIF(@mode = 1, N'ok   hadrlab3: restores in STANDBY (restore_mode 1)',
    N'FAIL hadrlab3: the restore mode is not STANDBY (@restore_mode = 1)');
INSERT @r SELECT CASE
    WHEN (SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE job_id IN (@copy, @restore)) < 2
        THEN N'FAIL hadrlab3: the copy job or the restore job of ex_logship is missing'
    WHEN EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE job_id IN (@copy, @restore) AND enabled = 1)
        THEN N'FAIL hadrlab3: the copy or the restore job is still enabled: disable both at the failover'
    ELSE N'ok   hadrlab3: copy and restore jobs exist, disabled since the failover' END;
DECLARE @probe datetime2(3), @after int, @state nvarchar(60) =
    CAST(DATABASEPROPERTYEX(N'ex_logship', 'Status') AS nvarchar(30));
IF @state = N'ONLINE'
BEGIN
    EXEC sys.sp_executesql N'SELECT @p = MIN(written_at) FROM ex_logship.dbo.Registration WHERE label = ''probe'';
        SELECT @a = COUNT(*) FROM ex_logship.dbo.Registration WHERE label = ''after failover'';',
        N'@p datetime2(3) OUTPUT, @a int OUTPUT', @p = @probe OUTPUT, @a = @after OUTPUT;
END;
INSERT @r SELECT IIF(@probe IS NOT NULL, N'ok   hadrlab3: the row ''probe'' is there',
    N'FAIL hadrlab3: no row with the label ''probe'' in ex_logship.dbo.Registration (or the database is not online)');
INSERT @r SELECT IIF(EXISTS (SELECT * FROM msdb.dbo.restorehistory AS r
                             JOIN msdb.dbo.backupset AS b ON b.backup_set_id = r.backup_set_id
                             WHERE r.destination_database_name = N'ex_logship' AND r.restore_type = 'L'
                               -- recovery 1 on a database still restoring afterwards: STANDBY
                               AND r.recovery = 1 AND b.backup_start_date >= @probe
                               AND CAST(b.last_lsn AS varchar(30)) <> '$(LSN)'),
    N'ok   hadrlab3: a log backup taken after the probe was restored in STANDBY',
    N'FAIL hadrlab3: no log backup taken after the row ''probe'' was restored in STANDBY: let the jobs ship it before the failover');
INSERT @r SELECT IIF(EXISTS (SELECT * FROM msdb.dbo.log_shipping_monitor_secondary
                             WHERE secondary_database = N'ex_logship' AND last_restored_file IS NOT NULL),
    N'ok   hadrlab3: the monitor saw a restore',
    N'FAIL hadrlab3: log_shipping_monitor_secondary has no restored file for ex_logship');
INSERT @r SELECT IIF(@state = N'ONLINE' AND DATABASEPROPERTYEX(N'ex_logship', 'IsInStandBy') = 0
                     AND DATABASEPROPERTYEX(N'ex_logship', 'Updateability') = N'READ_WRITE',
    N'ok   hadrlab3: ex_logship is online and writable',
    CONCAT(N'FAIL hadrlab3: ex_logship is ', ISNULL(@state, N'missing'),
           IIF(DATABASEPROPERTYEX(N'ex_logship', 'IsInStandBy') = 1, N' in STANDBY', N''),
           N', not online and writable: restore the tail WITH RECOVERY'));
DECLARE @restored varchar(30) = (SELECT CAST(MAX(b.last_lsn) AS varchar(30))
    FROM msdb.dbo.restorehistory AS r JOIN msdb.dbo.backupset AS b ON b.backup_set_id = r.backup_set_id
    WHERE r.destination_database_name = N'ex_logship' AND r.restore_type = 'L');
INSERT @r SELECT IIF(@restored = '$(LSN)',
    N'ok   hadrlab3: the last log backup of hadrlab1 is restored, up to the same LSN: no row lost',
    CONCAT(N'FAIL hadrlab3: last LSN restored ', ISNULL(@restored, N'none'), N', last LSN backed up on hadrlab1 $(LSN): ',
           N'the tail of hadrlab1 is not restored here'));
INSERT @r SELECT IIF(@after > 0, N'ok   hadrlab3: a row ''after failover'' was written',
    N'FAIL hadrlab3: no row ''after failover'': write one on the new primary');
SELECT line FROM @r ORDER BY n;
SQL
)
rc=$?
if [ $rc -ne 0 ] || [ -z "$secondary" ]; then echo "$secondary" | head -3; echo "FAIL hadrlab3 does not answer"; exit 1; fi
echo "$secondary"
if echo "$primary$secondary" | grep -q '^FAIL'; then echo "The log shipping and its failover are not done yet."; exit 1; fi
echo "Log shipping set up, shipped and failed over without loss."
