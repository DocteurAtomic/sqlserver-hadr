#!/usr/bin/env bash
# Exercise of module 5, a solution. Run after 1-start.sh. hadrlab2 gets BACKUP_PRIORITY = 0;
# hadrlab3 goes to synchronous commit, since sys.fn_hadr_backup_is_preferred_replica only
# chooses a secondary whose copy is SYNCHRONIZED (wait at most a minute), and gets
# ALLOW_CONNECTIONS = READ_ONLY. On hadrlab3: a full backup; a wait until hadrlab3 knows it as
# the differential base (at most a minute, a checkpoint on the primary at each turn); an
# invoice on hadrlab1, then a wait until hadrlab3 has redone it (a backup on a secondary stops
# where its redo is); a differential; another invoice, the same wait, a log backup. On
# hadrlab1: the chain restored as ex_backup_verif. Appends the result to
# evidence/module_05.md. Other solutions hold too: check.sh reads the state.
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
dir=/var/opt/mssql/share/ex_backup
redone() {  # waits until hadrlab3 has redone the last commit of ex_backup, at most a minute
    local lsn r
    lsn=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT last_commit_lsn FROM sys.dm_hadr_database_replica_states
          WHERE is_local = 1 AND database_id = DB_ID(N'ex_backup');" | tr -d '[:space:]')
    for i in $(seq 1 60); do
        r=$(sql hadrlab3 -h -1 -Q "SET NOCOUNT ON; SELECT IIF(last_redone_lsn > $lsn, 1, 0) FROM sys.dm_hadr_database_replica_states
            WHERE is_local = 1 AND database_id = DB_ID(N'ex_backup');" | tr -d '[:space:]')
        [ "$r" = 1 ] && return
        sql hadrlab1 -Q "USE ex_backup; CHECKPOINT;" >/dev/null
        sleep 1
    done
    echo "hadrlab3 has not redone the commit $lsn after a minute" >&2; exit 1
}
sql hadrlab1 -Q "SET NOCOUNT ON;
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab2' WITH (BACKUP_PRIORITY = 0);
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT);
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY));"
wait_ag_database hadrlab1 AgPacha ex_backup 60 hadrlab3
for i in $(seq 1 30); do
    [ "$(sql hadrlab3 -h -1 -Q "SET NOCOUNT ON; SELECT sys.fn_hadr_backup_is_preferred_replica(N'ex_backup');" | tr -d '[:space:]')" = 1 ] && break
    sleep 1
done
sql hadrlab3 -h -1 -v DIR="$dir" <<'SQL'
SET NOCOUNT ON;
IF sys.fn_hadr_backup_is_preferred_replica(N'ex_backup') <> 1
    THROW 50000, N'hadrlab3 is not the preferred replica for ex_backup', 1;
BACKUP DATABASE ex_backup TO DISK = N'$(DIR)/ex_backup-full.bak' WITH INIT, COMPRESSION, CHECKSUM;
SQL
sql hadrlab3 -h -1 -Q "SET NOCOUNT ON;
DECLARE @t0 datetime2(3) = SYSDATETIME(), @full numeric(25, 0) = (SELECT TOP (1) first_lsn FROM msdb.dbo.backupset
    WHERE database_name = N'ex_backup' AND type = 'D' AND is_copy_only = 0 AND server_name = @@SERVERNAME ORDER BY backup_set_id DESC);
WHILE ISNULL((SELECT differential_base_lsn FROM sys.master_files WHERE database_id = DB_ID(N'ex_backup') AND file_id = 1), 0) <> @full
      AND DATEDIFF(second, @t0, SYSDATETIME()) < 60
    WAITFOR DELAY '00:00:00.200';
IF ISNULL((SELECT differential_base_lsn FROM sys.master_files WHERE database_id = DB_ID(N'ex_backup') AND file_id = 1), 0) <> @full
    THROW 50000, N'hadrlab3 does not know its full backup as the differential base after a minute', 1;" &
waiter=$!
for i in $(seq 1 60); do
    kill -0 $waiter 2>/dev/null || break
    sql hadrlab1 -Q "USE ex_backup; CHECKPOINT;" >/dev/null
    sleep 1
done
wait $waiter
sql hadrlab1 -Q "EXEC ex_backup.dbo.AddInvoice;" >/dev/null
redone
sql hadrlab3 -Q "SET NOCOUNT ON; BACKUP DATABASE ex_backup TO DISK = N'$dir/ex_backup-diff.bak' WITH INIT, COMPRESSION, CHECKSUM, DIFFERENTIAL;"
sql hadrlab1 -Q "EXEC ex_backup.dbo.AddInvoice;" >/dev/null
redone
sql hadrlab3 -Q "SET NOCOUNT ON; BACKUP LOG ex_backup TO DISK = N'$dir/ex_backup-log.trn' WITH INIT, COMPRESSION, CHECKSUM;"
sql hadrlab1 <<SQL
SET NOCOUNT ON;
RESTORE DATABASE ex_backup_verif FROM DISK = N'$dir/ex_backup-full.bak' WITH NORECOVERY, REPLACE,
    MOVE N'ex_backup' TO N'/var/opt/mssql/data/ex_backup_verif.mdf', MOVE N'ex_backup_log' TO N'/var/opt/mssql/data/ex_backup_verif_log.ldf';
RESTORE DATABASE ex_backup_verif FROM DISK = N'$dir/ex_backup-diff.bak' WITH NORECOVERY;
RESTORE LOG ex_backup_verif FROM DISK = N'$dir/ex_backup-log.trn' WITH RECOVERY;
SELECT COUNT(*) AS invoices FROM ex_backup_verif.dbo.Invoice;
SQL
n=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM ex_backup_verif.dbo.Invoice;" | tr -d '[:space:]')
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 5, exercise, ex_backup backed up on hadrlab3 (made synchronous to be the preferred replica, hadrlab2 at BACKUP_PRIORITY 0), full, differential and log restored on hadrlab1: ${n} invoices of ${n}; three containers on one host" >> evidence/module_05.md
