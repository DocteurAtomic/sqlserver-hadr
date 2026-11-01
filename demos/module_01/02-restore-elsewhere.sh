#!/usr/bin/env bash
# Clip 1.1: hadrlab1 is lost. Restores the chain of m01_registration on hadrlab2 from the
# shared volume (full, differential, the log backups after it), times it, and counts what
# came back against what hadrlab1 had. The time is the RTO of this solution, the rows that
# did not come back are its RPO. Appends both to evidence/module_01.md. Run after
# 00-setup.sh; hadrlab1 stays as it is (the clip pretends it is gone).
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
start=$(date +%s.%N)
sql hadrlab2 <<'SQL'
SET NOCOUNT ON;
DECLARE @t0 datetime2(3) = SYSDATETIME();
RESTORE DATABASE m01_registration FROM DISK = N'/var/opt/mssql/share/m01_registration-full.bak'
    WITH NORECOVERY, REPLACE;
RESTORE DATABASE m01_registration FROM DISK = N'/var/opt/mssql/share/m01/m01_registration_diff1.bak'
    WITH NORECOVERY, CHECKSUM;
RESTORE LOG m01_registration FROM DISK = N'/var/opt/mssql/share/m01/m01_registration_log2.trn'
    WITH NORECOVERY, CHECKSUM;
RESTORE LOG m01_registration FROM DISK = N'/var/opt/mssql/share/m01/m01_registration_log3.trn'
    WITH RECOVERY, CHECKSUM;
SELECT @@SERVERNAME AS server, DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0 AS restore_seconds;
GO
SQL
elapsed=$(awk -v s=$start -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }')
count='SET NOCOUNT ON; SELECT OrderReference, COUNT(*) FROM m01_registration.Enrollment.Enrollment
       WHERE OrderReference LIKE '"'"'m01 batch%'"'"' GROUP BY OrderReference ORDER BY 1;'
a=$(mktemp); b=$(mktemp)
sql hadrlab1 -h -1 -s '|' -Q "$count" | LC_ALL=C sort > "$a"
sql hadrlab2 -h -1 -s '|' -Q "$count" | LC_ALL=C sort > "$b"
echo "batch|on hadrlab1|on hadrlab2"
join -t '|' -a 1 -e 0 -o 0,1.2,2.2 "$a" "$b"
lost=$(join -t '|' -a 1 -e 0 -o 1.2,2.2 "$a" "$b" | awk -F'|' '{ s += $1 - $2 } END { print s }')
rm -f "$a" "$b"
echo "registrations lost: $lost; restore on hadrlab2, end to end: $elapsed s"
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 1, backups only (full, differential, log every 5 s): \
restore of m01_registration on hadrlab2 in $elapsed s end to end (1.4 GB used, compressed backups on the shared volume, three containers on one host); \
$lost registrations lost, those written after the last log backup" >> evidence/module_01.md
