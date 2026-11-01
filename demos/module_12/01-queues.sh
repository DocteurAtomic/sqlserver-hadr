#!/usr/bin/env bash
# Clip 12.1: the queues of the group, and what they say of a failover. Reads setup/ag-health.sql
# on hadrlab1, the primary of AgPacha: one line per secondary copy, the log not yet sent
# (send_q_kb), the log received but not yet redone (redo_q_kb) and the redo rate, the estimated
# redo time of a failover (est_redo_s, the RTO part that depends on the replica) and the
# estimated data loss (est_loss_s, the RPO). Three moments:
#   1. the group at rest;
#   2. a load of 100,000 rows (about 200 MB of log) on hadrlab1, read every second while it runs;
#   3. the copy of hadrlab3 suspended, then ten seconds of writes on hadrlab1 (20 batches of
#      500 rows), read; then resumed, read every second until its queues are empty.
# Run after 00-setup.sh. Leaves AgPacha as it found it.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
health() { sql hadrlab1 -h -1 < setup/ag-health.sql | cut -d' ' -f2,4- | sed "s/^/  ${1:-}/"; }
header() { echo "  ${1:-}replica connected sync suspended send_q_kb redo_q_kb redo_kb_s est_redo_s est_loss_s"; }
echo "== 1. hadrlab1: AgPacha at rest"
header; health
echo
echo "== 2. hadrlab1: 100,000 rows of 2 KB into m12_registration, the health every second"
out=$(mktemp); trap 'rm -f "$out"' EXIT
sql hadrlab1 -h -1 > "$out" 2>&1 <<'SQL' &
SET NOCOUNT ON;
DECLARE @t0 datetime2(3) = SYSDATETIME();
INSERT m12_registration.dbo.Registration (email)
SELECT TOP (100000) 'load@pachadata.example' FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;
SELECT CONCAT(N'load: 100000 rows committed in ', DATEDIFF(millisecond, @t0, SYSDATETIME()), N' ms');
SQL
load=$!
header "     "
for i in 0 1 2 3 4 5; do
    health "+$i s "
    kill -0 $load 2>/dev/null || break
    sleep 1
done
wait $load
sed 's/^/  /' "$out"
sleep 2
echo "-- 2 s after the load"
health "     "
echo
echo "== 3. hadrlab3: SET HADR SUSPEND, then ten seconds of writes on hadrlab1"
sql hadrlab3 -Q "ALTER DATABASE m12_registration SET HADR SUSPEND;"
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @i int = 0, @t0 datetime2(3) = SYSDATETIME();
WHILE @i < 20
BEGIN
    INSERT m12_registration.dbo.Registration (email)
    SELECT TOP (500) 'suspended@pachadata.example' FROM sys.all_objects;
    SET @i += 1;
    WAITFOR DELAY '00:00:00.500';
END;
SELECT CONCAT(N'  hadrlab1: ', COUNT(*), N' rows committed in ',
              DATEDIFF(millisecond, @t0, SYSDATETIME()), N' ms while hadrlab3 is suspended')
FROM m12_registration.dbo.Registration WHERE email = 'suspended@pachadata.example' AND written_at >= @t0;
SQL
header; health
echo
echo "== 3. hadrlab3: SET HADR RESUME"
sql hadrlab3 -Q "ALTER DATABASE m12_registration SET HADR RESUME;"
header "     "
# SYNCHRONIZING comes back at once; the redo queue and the loss estimate empty after.
for i in $(seq 0 30); do
    line=$(health "+$i s " | grep hadrlab3)
    echo "$line"
    set -- $line
    [ "$8" = 0 ] && [ "${11}" = .0 ] && break   # redo_q_kb 0, est_loss_s 0
    sleep 1
done
