#!/usr/bin/env bash
# Clip 5.3: back up on a secondary, and restore the chain elsewhere. The backup step of a job,
# the same on every replica: it backs up only where sys.fn_hadr_backup_is_preferred_replica
# answers 1, which is hadrlab2 with the defaults (on hadrlab1 it says so and does nothing).
# On hadrlab2, without COPY_ONLY: a full backup, then at once a differential, which still
# rests on the previous full (the one 00-setup.sh took on hadrlab1). Then a wait, at most a
# minute, until hadrlab2 knows its own full as the new differential base
# (sys.master_files.differential_base_lsn), with a checkpoint on the primary at each turn: the
# change reaches the secondary through the log. A row written on hadrlab1, a second
# differential, a second row, a log backup, each backup once hadrlab2 has redone the row: a
# backup on a secondary stops where its redo is, which can be behind what it has hardened. The history in msdb of hadrlab2. Then the chain
# restored on hadrlab1 as m05_verif: the full, the first differential (Msg 3136), the second
# one, the log, and the two rows found. Appends the measures to evidence/module_05.md.
# Run after 00-setup.sh; it can run again.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
dir=/var/opt/mssql/share/m05
redone() {  # waits until hadrlab2 has redone the last commit of m05_reports on the primary, at
           # most a minute, a checkpoint on the primary at each turn (it writes the log that moves
           # the redo forward): a backup on a secondary only holds what that secondary has redone.
           # Prints how long it took.
    local lsn t=$(date +%s.%N) r
    lsn=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT last_commit_lsn FROM sys.dm_hadr_database_replica_states
          WHERE is_local = 1 AND database_id = DB_ID(N'm05_reports');" | tr -d '[:space:]')
    for i in $(seq 1 60); do
        r=$(sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; SELECT IIF(last_redone_lsn > $lsn, 1, 0) FROM sys.dm_hadr_database_replica_states
            WHERE is_local = 1 AND database_id = DB_ID(N'm05_reports');" | tr -d '[:space:]')
        [ "$r" = 1 ] && { echo "  hadrlab2 has redone the commit $lsn, after $(awk -v s=$t -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }') s"; return; }
        sql hadrlab1 -Q "USE m05_reports; CHECKPOINT;" >/dev/null
        sleep 1
    done
    echo "hadrlab2 has not redone the commit $lsn after a minute" >&2; exit 1
}
job_step() {  # the backup step of the job, on one instance
    sql $1 -h -1 -v DIR="$dir" <<'SQL'
SET NOCOUNT ON;
IF sys.fn_hadr_backup_is_preferred_replica(N'm05_reports') <> 1
BEGIN
    PRINT CONCAT(N'  ', @@SERVERNAME, N': not the preferred replica for m05_reports, nothing to do');
    RETURN;
END;
DECLARE @t0 datetime2(3) = SYSDATETIME();
BACKUP DATABASE m05_reports TO DISK = N'$(DIR)/m05_reports-full.bak' WITH INIT, COMPRESSION, CHECKSUM;
PRINT CONCAT(N'  ', @@SERVERNAME, N': full backup of m05_reports in ', DATEDIFF(millisecond, @t0, SYSDATETIME()), N' ms');
SQL
}
base_state() {  # the differential base known by hadrlab2, against its last full
    sql hadrlab2 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  hadrlab2: differential_base_lsn ', ISNULL(CONVERT(varchar(30), f.differential_base_lsn), 'NULL'), N', its last full ', b.first_lsn,
              IIF(ISNULL(f.differential_base_lsn, 0) = b.first_lsn, N' (the same)', N' (not yet)'))
FROM sys.master_files AS f
CROSS APPLY (SELECT TOP (1) first_lsn FROM msdb.dbo.backupset
             WHERE database_name = N'm05_reports' AND type = 'D' AND is_copy_only = 0 AND server_name = @@SERVERNAME
             ORDER BY backup_set_id DESC) AS b
WHERE f.database_id = DB_ID(N'm05_reports') AND f.file_id = 1;"
}
# The two rows of a previous run go, so that the script can run again.
sql hadrlab1 -Q "SET NOCOUNT ON; DELETE m05_reports.dbo.Enrollment WHERE id IN (900001, 900002);"
echo "== the backup step of the job, on hadrlab1 then on hadrlab2"
job_step hadrlab1
job_step hadrlab2
base_state
echo
echo "== hadrlab2: at once, a differential"
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; BACKUP DATABASE m05_reports TO DISK = N'$dir/m05_reports-diff-at-once.bak' WITH INIT, COMPRESSION, CHECKSUM, DIFFERENTIAL;" | grep '^BACKUP'
echo
echo "== hadrlab2: waiting for the new differential base (at most a minute)"
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON;
DECLARE @t0 datetime2(3) = SYSDATETIME(), @full numeric(25, 0) = (SELECT TOP (1) first_lsn FROM msdb.dbo.backupset
    WHERE database_name = N'm05_reports' AND type = 'D' AND is_copy_only = 0 AND server_name = @@SERVERNAME ORDER BY backup_set_id DESC);
WHILE ISNULL((SELECT differential_base_lsn FROM sys.master_files WHERE database_id = DB_ID(N'm05_reports') AND file_id = 1), 0) <> @full
      AND DATEDIFF(second, @t0, SYSDATETIME()) < 60
    WAITFOR DELAY '00:00:00.200';
IF ISNULL((SELECT differential_base_lsn FROM sys.master_files WHERE database_id = DB_ID(N'm05_reports') AND file_id = 1), 0) <> @full
    THROW 50000, N'hadrlab2 does not know its full backup as the differential base after a minute', 1;
PRINT CONCAT(N'  known ', FORMAT(DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0, N'0.0'), N' s after the differential');" &
waiter=$!
# The new base reaches the secondary through the log of the primary: a checkpoint writes some.
for i in $(seq 1 60); do
    kill -0 $waiter 2>/dev/null || break
    sql hadrlab1 -Q "USE m05_reports; CHECKPOINT;" >/dev/null
    sleep 1
done
wait $waiter
base_state
echo
echo "== hadrlab1: a first row; hadrlab2: a second differential; hadrlab1: a second row; hadrlab2: a log backup"
sql hadrlab1 -Q "SET NOCOUNT ON; INSERT m05_reports.dbo.Enrollment (id, session_id, enrolled_at, email) VALUES (900001, 1, SYSDATETIME(), 'after-full@pachadata.example');"
redone
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; BACKUP DATABASE m05_reports TO DISK = N'$dir/m05_reports-diff.bak' WITH INIT, COMPRESSION, CHECKSUM, DIFFERENTIAL;" | grep '^BACKUP'
sql hadrlab1 -Q "SET NOCOUNT ON; INSERT m05_reports.dbo.Enrollment (id, session_id, enrolled_at, email) VALUES (900002, 1, SYSDATETIME(), 'after-diff@pachadata.example');"
redone
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; BACKUP LOG m05_reports TO DISK = N'$dir/m05_reports-log.trn' WITH INIT, COMPRESSION, CHECKSUM;" | grep '^BACKUP'
echo
echo "== hadrlab2: the history in msdb"
sql hadrlab2 -Q "SET NOCOUNT ON;
SELECT b.type, b.is_copy_only, b.server_name, b.first_lsn, b.differential_base_lsn, m.physical_device_name AS device
FROM msdb.dbo.backupset AS b JOIN msdb.dbo.backupmediafamily AS m ON m.media_set_id = b.media_set_id
WHERE b.database_name = N'm05_reports' ORDER BY b.backup_set_id;"
echo
echo "== hadrlab1: the chain restored as m05_verif"
restore() {  # one restore statement on hadrlab1; an error is printed, not fatal
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; $1" 2>&1 | grep -v '^Processed' | sed 's/^/  /' || true
}
restore "RESTORE DATABASE m05_verif FROM DISK = N'$dir/m05_reports-full.bak' WITH NORECOVERY, REPLACE,
    MOVE N'm05_reports' TO N'/var/opt/mssql/data/m05_verif.mdf', MOVE N'm05_reports_log' TO N'/var/opt/mssql/data/m05_verif_log.ldf';"
echo "  -- the differential taken at once:"
restore "RESTORE DATABASE m05_verif FROM DISK = N'$dir/m05_reports-diff-at-once.bak' WITH NORECOVERY;"
echo "  -- the differential taken once the base was known:"
restore "RESTORE DATABASE m05_verif FROM DISK = N'$dir/m05_reports-diff.bak' WITH NORECOVERY;"
restore "RESTORE LOG m05_verif FROM DISK = N'$dir/m05_reports-log.trn' WITH RECOVERY;"
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  m05_verif ', CONVERT(nvarchar(20), DATABASEPROPERTYEX(N'm05_verif', 'Status')), N': ', COUNT(*), N' enrollments, ',
              SUM(IIF(id IN (900001, 900002), 1, 0)), N' of the two rows written after the full')
FROM m05_verif.dbo.Enrollment;"
got=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM m05_verif.dbo.Enrollment WHERE id IN (900001, 900002);" | tr -d '[:space:]')
[ "$got" = 2 ] || { echo "m05_verif does not have the two rows" >&2; exit 1; }
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 5, backups of m05_reports on hadrlab2 (secondary) without COPY_ONLY: the differential taken right after the full rested on the previous full and was refused at restore (Msg 3136); the chain full, differential, log restored on hadrlab1, both rows written after the full found; three containers on one host" >> evidence/module_05.md
