#!/usr/bin/env bash
# Exercise of module 5: checks the backup and reading setup of ex_backup. It reads the state,
# never a script. It waits only for the answer of the backup preference to settle (at most
# ten readings, a second apart) and for its connections (at most 10 seconds to log in).
# On hadrlab1: ex_backup a database of AgPacha; AUTOMATED_BACKUP_PREFERENCE that keeps the
# backups off the primary (SECONDARY or SECONDARY_ONLY). On each instance:
# sys.fn_hadr_backup_is_preferred_replica('ex_backup'), 1 on hadrlab3 and 0 elsewhere. On
# hadrlab3: in msdb, a full backup (not COPY_ONLY), a differential and a log backup of
# ex_backup taken there. On hadrlab1: ex_backup_verif online, restored from a full, a
# differential and a log backup that all come from hadrlab3, with at least two invoices more
# than the 1,000 of the start. From the sqlcmd of the container hadrlab1: a connection to
# hadrlab3 with ex_backup and ApplicationIntent=ReadOnly lands on hadrlab3, in READ_ONLY, and
# the same connection without the intent is refused (READ_ONLY, not ALL).
# Exits with 0 when everything holds, with 1 otherwise, saying what is missing.
# Usage: ./exercises/module_05/check.sh     (with Podman: ENGINE=podman ...)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
all=""
say() { echo "$1"; all="$all
$1"; }
out=$(sql hadrlab1 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
DECLARE @r TABLE (n int IDENTITY, line nvarchar(400));
INSERT @r SELECT IIF(EXISTS (SELECT * FROM sys.availability_databases_cluster AS d
                             JOIN sys.availability_groups AS g ON g.group_id = d.group_id
                             WHERE g.name = N'AgPacha' AND d.database_name = N'ex_backup'),
    N'ok   hadrlab1: ex_backup is a database of AgPacha',
    N'FAIL hadrlab1: ex_backup is not in AgPacha: run exercises/module_05/1-start.sh');
INSERT @r SELECT CASE
    WHEN automated_backup_preference_desc IN (N'secondary', N'secondary_only')
        THEN CONCAT(N'ok   hadrlab1: AUTOMATED_BACKUP_PREFERENCE = ', UPPER(automated_backup_preference_desc))
    ELSE CONCAT(N'FAIL hadrlab1: AUTOMATED_BACKUP_PREFERENCE = ', UPPER(automated_backup_preference_desc),
                N': the backups must stay off the primary') END
FROM sys.availability_groups WHERE name = N'AgPacha';
-- The restore sequence of ex_backup_verif: the last full restored, and what followed it.
DECLARE @full int = (SELECT MAX(restore_history_id) FROM msdb.dbo.restorehistory
                     WHERE destination_database_name = N'ex_backup_verif' AND restore_type = 'D');
DECLARE @seq TABLE (restore_type char(1), server_name sysname NULL, is_copy_only bit, database_name sysname NULL);
INSERT @seq SELECT h.restore_type, b.server_name, b.is_copy_only, b.database_name
FROM msdb.dbo.restorehistory AS h JOIN msdb.dbo.backupset AS b ON b.backup_set_id = h.backup_set_id
WHERE h.destination_database_name = N'ex_backup_verif' AND h.restore_history_id >= @full;
INSERT @r SELECT CASE
    WHEN DB_ID(N'ex_backup_verif') IS NULL THEN N'FAIL hadrlab1: no database ex_backup_verif: restore the chain here under that name'
    WHEN DATABASEPROPERTYEX(N'ex_backup_verif', 'Status') <> N'ONLINE'
        THEN CONCAT(N'FAIL hadrlab1: ex_backup_verif is ', CONVERT(nvarchar(60), DATABASEPROPERTYEX(N'ex_backup_verif', 'Status')),
                    N': the last restore needs WITH RECOVERY')
    ELSE N'ok   hadrlab1: ex_backup_verif is online' END;
INSERT @r SELECT CASE
    WHEN @full IS NULL THEN N'FAIL hadrlab1: ex_backup_verif has no restore of a full backup in msdb'
    WHEN NOT EXISTS (SELECT * FROM @seq WHERE restore_type = 'D' AND server_name = N'hadrlab3' AND is_copy_only = 0 AND database_name = N'ex_backup')
        THEN N'FAIL hadrlab1: the full backup restored in ex_backup_verif was not taken on hadrlab3 (or is COPY_ONLY)'
    ELSE N'ok   hadrlab1: ex_backup_verif restored from a full backup taken on hadrlab3' END;
INSERT @r SELECT IIF(EXISTS (SELECT * FROM @seq WHERE restore_type = 'I' AND server_name = N'hadrlab3'),
    N'ok   hadrlab1: then a differential backup taken on hadrlab3',
    N'FAIL hadrlab1: no differential backup taken on hadrlab3 restored after the full one (Msg 3136? read the clip 5.3)');
INSERT @r SELECT IIF(EXISTS (SELECT * FROM @seq WHERE restore_type = 'L' AND server_name = N'hadrlab3'),
    N'ok   hadrlab1: then a log backup taken on hadrlab3',
    N'FAIL hadrlab1: no log backup taken on hadrlab3 restored after the differential');
IF DATABASEPROPERTYEX(N'ex_backup_verif', 'Status') = N'ONLINE'
    INSERT @r SELECT CASE WHEN COUNT(*) >= 1002
        THEN CONCAT(N'ok   hadrlab1: ex_backup_verif has ', COUNT(*), N' invoices')
        ELSE CONCAT(N'FAIL hadrlab1: ex_backup_verif has ', COUNT(*), N' invoices: run dbo.AddInvoice on hadrlab1 after the full backup and after the differential, then back up and restore again') END
    FROM ex_backup_verif.dbo.Invoice;
SELECT line FROM @r ORDER BY n;
SQL
)
rc=$?
if [ $rc -ne 0 ] || [ -z "$out" ]; then echo "$out" | head -3; echo "FAIL hadrlab1 does not answer"; exit 1; fi
say "$out"
# The answer of the function follows the state of the copies, which a backup or a restore can
# disturb for a moment: read it up to ten times, a second apart, with a checkpoint on the
# primary (it writes the log that keeps the copies moving), until it is the expected one.
pref() { for n in $nodes; do printf '%s=%s ' $n "$(sql $n -h -1 -Q "SET NOCOUNT ON; SELECT sys.fn_hadr_backup_is_preferred_replica(N'ex_backup');" 2>&1 | tr -d '[:space:]')"; done; }
for i in $(seq 1 10); do
    p=$(pref)
    [ "$p" = "hadrlab1=0 hadrlab2=0 hadrlab3=1 " ] && break
    sql hadrlab1 -Q "IF DB_ID(N'ex_backup') IS NOT NULL EXEC (N'USE ex_backup; CHECKPOINT;');" >/dev/null 2>&1
    sleep 1
done
for kv in $p; do
    n=${kv%%=*}; got=${kv#*=}; want=0; [ $n = hadrlab3 ] && want=1
    if [ "$got" = "$want" ]; then say "ok   $n: fn_hadr_backup_is_preferred_replica('ex_backup') = $got"
    else say "FAIL $n: fn_hadr_backup_is_preferred_replica('ex_backup') = $got, $want expected"; fi
done
out=$(sql hadrlab3 -h -1 <<'SQL' 2>&1
SET NOCOUNT ON;
DECLARE @since datetime = (SELECT create_date FROM sys.databases WHERE name = N'ex_backup');
SELECT CASE
    WHEN EXISTS (SELECT * FROM msdb.dbo.backupset WHERE database_name = N'ex_backup' AND server_name = @@SERVERNAME
                 AND type = t.type AND is_copy_only = 0 AND backup_finish_date >= @since)
        THEN CONCAT(N'ok   hadrlab3: a ', t.label, N' of ex_backup taken here')
    ELSE CONCAT(N'FAIL hadrlab3: no ', t.label, N' of ex_backup taken here', IIF(t.type = 'D', N' (without COPY_ONLY)', N'')) END
FROM (VALUES ('D', N'full backup', 1), ('I', N'differential backup', 2), ('L', N'log backup', 3)) AS t (type, label, n)
ORDER BY t.n;
SQL
)
if [ -z "$out" ]; then echo "FAIL hadrlab3 does not answer"; exit 1; fi
say "$out"
ro=$(lands_on hadrlab1 hadrlab3 -d ex_backup -K ReadOnly)
if [ "$ro" = "hadrlab3 ex_backup READ_ONLY" ]; then say "ok   from the container hadrlab1, hadrlab3 -d ex_backup -K ReadOnly lands on: $ro"
else say "FAIL from the container hadrlab1, hadrlab3 -d ex_backup -K ReadOnly: $ro"; fi
rw=$(lands_on hadrlab1 hadrlab3 -d ex_backup)
case $rw in
    *"application intent is set to read only"*) say "ok   from the container hadrlab1, hadrlab3 -d ex_backup without the intent is refused: READ_ONLY" ;;
    *) say "FAIL from the container hadrlab1, hadrlab3 -d ex_backup without the intent: $rw (ALLOW_CONNECTIONS = READ_ONLY expected)" ;;
esac
if echo "$all" | grep -q '^FAIL'; then echo "The backups of ex_backup are not on hadrlab3 yet, or the chain is not restored, or hadrlab3 is not open to the reports."; exit 1; fi
echo "ex_backup is backed up on hadrlab3, its chain restores on hadrlab1, and hadrlab3 serves the reports."
