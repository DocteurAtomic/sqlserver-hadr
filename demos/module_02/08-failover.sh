#!/usr/bin/env bash
# Clip 2.4: the planned failover of m02_registration from hadrlab1 to hadrlab2, in the order
# of Learn ("Fail over to a log shipping secondary"). First the last registrations of
# hadrlab1, and what hadrlab2 has of them at that moment: what a lost hadrlab1 would have
# cost. Then: the backup job of hadrlab1 disabled; the copy and the restore run once more on
# hadrlab2, then disabled; the tail of the log backed up on hadrlab1 WITH NORECOVERY, which
# leaves it RESTORING; that backup restored on hadrlab2 WITH RECOVERY. Counts the rows on both
# sides, writes a row on hadrlab2, and appends the lost rows and the duration to
# evidence/module_02.md. Run after 03-ship-by-hand.sh (and 07-alert.sh, if played).
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
batches='SET NOCOUNT ON; SELECT OrderReference, COUNT(*) FROM m02_registration.Enrollment.Enrollment
         WHERE OrderReference LIKE '"'"'m02 batch%'"'"' GROUP BY OrderReference ORDER BY 1;'
echo "hadrlab1, the last registrations before the failover:"
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; EXEC m02_registration.dbo.m02_register 40, 'm02 batch last';"
a=$(mktemp); b=$(mktemp); trap 'rm -f "$a" "$b"' EXIT
sql hadrlab1 -h -1 -s '|' -Q "$batches" | LC_ALL=C sort > "$a"
sql hadrlab2 -h -1 -s '|' -Q "$batches" | LC_ALL=C sort > "$b"
echo "batch|on hadrlab1|on hadrlab2 (STANDBY), now"
join -t '|' -a 1 -e 0 -o 0,1.2,2.2 "$a" "$b"
exposed=$(join -t '|' -a 1 -e 0 -o 1.2,2.2 "$a" "$b" | awk -F'|' '{ s += $1 - $2 } END { print s }')
echo "rows that a lost hadrlab1 would take with it now: $exposed"
echo
start=$(date +%s.%N)
echo "1. hadrlab1: the backup job disabled, a run in progress waited for."
disable_job hadrlab1 LSBackup_m02_registration
echo "2. hadrlab2: what is on the share copied and restored, then the two jobs disabled."
run_job hadrlab2 LSCopy_m02_registration
run_job hadrlab2 LSRestore_m02_registration
disable_job hadrlab2 LSCopy_m02_registration
disable_job hadrlab2 LSRestore_m02_registration
echo "3. hadrlab1: the tail of the log, WITH NORECOVERY."
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
BACKUP LOG m02_registration TO DISK = N'/var/opt/mssql/share/logship/m02_registration_tail.trn'
    WITH INIT, NORECOVERY, COMPRESSION, CHECKSUM;
SELECT name, state_desc AS state FROM sys.databases WHERE name = N'm02_registration';
SQL
echo "4. hadrlab2: the tail restored WITH RECOVERY."
sql hadrlab2 <<'SQL'
SET NOCOUNT ON;
RESTORE LOG m02_registration FROM DISK = N'/var/opt/mssql/share/logship/m02_registration_tail.trn'
    WITH RECOVERY, CHECKSUM;
SELECT name, state_desc AS state, is_in_standby, is_read_only FROM sys.databases WHERE name = N'm02_registration';
SQL
elapsed=$(awk -v s=$start -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }')
echo
sql hadrlab2 -h -1 -s '|' -Q "$batches" | LC_ALL=C sort > "$b"
echo "batch|on hadrlab1 before the tail|on hadrlab2 after the failover"
join -t '|' -a 1 -e 0 -o 0,1.2,2.2 "$a" "$b"
lost=$(join -t '|' -a 1 -e 0 -o 1.2,2.2 "$a" "$b" | awk -F'|' '{ s += $1 - $2 } END { print s }')
echo "rows lost: $lost; failover, from the backup job disabled to hadrlab2 online: $elapsed s"
echo
echo "hadrlab2 takes the writes:"
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; EXEC m02_registration.dbo.m02_register 5, 'm02 after failover';
    SELECT CONCAT(@@SERVERNAME, ': ', COUNT(*), ' rows of m02 after failover')
    FROM m02_registration.Enrollment.Enrollment WHERE OrderReference = 'm02 after failover';"
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 2, log shipping, planned failover of m02_registration from hadrlab1 to hadrlab2 (tail of the log WITH NORECOVERY, three containers on one host): $lost rows lost, $elapsed s from the backup job disabled to the secondary online; at that moment, a lost primary would have taken $exposed rows with it" >> evidence/module_02.md
