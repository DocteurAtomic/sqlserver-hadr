#!/usr/bin/env bash
# Clip 5.3: the backup preference of the group, and what sys.fn_hadr_backup_is_preferred_replica
# answers on each instance. The function decides where a backup job works; SQL Server enforces
# nothing. Read on the three instances for m05_reports: with the defaults (SECONDARY, every
# priority at 50); with PRIMARY; back to SECONDARY with BACKUP_PRIORITY = 100 for hadrlab3, the
# asynchronous secondary, which the function still does not choose; with the copy of
# m05_reports suspended on hadrlab2 (for that database only, PachadataTraining shown beside
# it). Each change is read again until every instance agrees, at most 30 seconds. Then a log
# backup taken by hand on hadrlab3, where the function answers 0: it succeeds. The settings go
# back to their defaults, the copy of hadrlab2 is resumed and SYNCHRONIZED again (at most a
# minute). Appends the result to evidence/module_05.md. Run after 00-setup.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
answers() {  # one line: the function on the three instances, for m05_reports and PachadataTraining
    for n in $nodes; do
        sql $n -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(@@SERVERNAME, N' ', sys.fn_hadr_backup_is_preferred_replica(N'm05_reports'),
                         N'/', sys.fn_hadr_backup_is_preferred_replica(N'PachadataTraining'))"
    done | paste -sd' ' | sed 's/ hadrlab/   hadrlab/g'
}
settle() {  # waits until two readings a second apart agree, at most 30 seconds, then prints one
    local a b
    a=$(answers)
    for i in $(seq 1 30); do
        sleep 1; b=$(answers)
        [ "$a" = "$b" ] && break
        a=$b
    done
    echo "  preferred for m05_reports/PachadataTraining: $b"
}
settings() {
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  AUTOMATED_BACKUP_PREFERENCE = ', g.automated_backup_preference_desc, N'; BACKUP_PRIORITY ',
              STRING_AGG(CONCAT(ar.replica_server_name, N' ', ar.backup_priority, N' (', LOWER(ar.availability_mode_desc), N')'), N', ')
              WITHIN GROUP (ORDER BY ar.replica_server_name))
FROM sys.availability_groups AS g JOIN sys.availability_replicas AS ar ON ar.group_id = g.group_id
GROUP BY g.automated_backup_preference_desc;"
}
echo "== the defaults"
settings
settle
echo
echo "== AUTOMATED_BACKUP_PREFERENCE = PRIMARY"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha SET (AUTOMATED_BACKUP_PREFERENCE = PRIMARY);"
settings
settle
echo
echo "== back to SECONDARY, BACKUP_PRIORITY = 100 for hadrlab3"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha SET (AUTOMATED_BACKUP_PREFERENCE = SECONDARY);
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (BACKUP_PRIORITY = 100);"
settings
settle
sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, ar.availability_mode_desc AS mode, DB_NAME(d.database_id) AS db,
       d.synchronization_state_desc AS sync
FROM sys.dm_hadr_database_replica_states AS d JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
WHERE d.is_local = 0 AND d.database_id = DB_ID(N'm05_reports') ORDER BY ar.replica_server_name;"
echo
echo "== hadrlab2: SET HADR SUSPEND for m05_reports"
sql hadrlab2 -Q "ALTER DATABASE m05_reports SET HADR SUSPEND;"
settle
echo
echo "== hadrlab3, where the function answers 0 for m05_reports: a log backup by hand"
sql hadrlab3 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  fn_hadr_backup_is_preferred_replica: ', sys.fn_hadr_backup_is_preferred_replica(N'm05_reports'));
BACKUP LOG m05_reports TO DISK = N'/var/opt/mssql/share/m05/m05_reports-byhand-hadrlab3.trn' WITH INIT, COMPRESSION;" 2>&1 | grep -v '^Processed'
echo
echo "== back to the defaults"
resume_copy hadrlab2 m05_reports
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (BACKUP_PRIORITY = 50);"
wait_ag_database hadrlab1 AgPacha m05_reports 60 hadrlab2
settings
settle
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 5, sys.fn_hadr_backup_is_preferred_replica with AUTOMATED_BACKUP_PREFERENCE = SECONDARY: 1 on hadrlab2 (synchronous, SYNCHRONIZED) only, never on hadrlab3 (asynchronous, SYNCHRONIZING) even at BACKUP_PRIORITY 100; 1 on the primary once the copy of hadrlab2 is suspended; three containers on one host" >> evidence/module_05.md
