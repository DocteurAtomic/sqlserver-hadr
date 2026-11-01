#!/usr/bin/env bash
# Clip 12.1: a replica that the primary does not see any more. The database mirroring endpoint
# of hadrlab3 stopped (ALTER ENDPOINT ... STATE = STOPPED): it is shared by every group of the
# instance, which is why the exercise never breaks it. hadrlab1 sees hadrlab3 DISCONNECTED
# after a few seconds (read every second, 30 seconds at most); its queues and both estimates
# are then NULL: the primary knows neither what it has not sent nor how far the copy is. Five
# seconds of writes on hadrlab1, read again, then the endpoint started again, and the time
# until hadrlab3 is connected and caught up. Run after 01-queues.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
health() { sql hadrlab1 -h -1 < setup/ag-health.sql | cut -d' ' -f2,4- | sed "s/^/  ${1:-}/"; }
header() { echo "  ${1:-}replica connected sync suspended send_q_kb redo_q_kb redo_kb_s est_redo_s est_loss_s"; }
since() { awk -v a="$1" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }'; }
connected_of() {
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT rs.connected_state_desc FROM sys.dm_hadr_availability_replica_states AS rs
        JOIN sys.availability_replicas AS ar ON ar.replica_id = rs.replica_id
        JOIN sys.availability_groups AS g ON g.group_id = ar.group_id
        WHERE g.name = N'AgPacha' AND ar.replica_server_name = N'hadrlab3';" | tr -d '[:space:]'
}
echo "== hadrlab3: ALTER ENDPOINT hadr_endpoint STATE = STOPPED ($(date -u +%T) UTC)"
sql hadrlab3 -Q "ALTER ENDPOINT hadr_endpoint STATE = STOPPED;"
t0=$(date +%s.%N)
for i in $(seq 1 30); do
    [ "$(connected_of)" = DISCONNECTED ] && break
    sleep 1
done
echo "  hadrlab1 sees hadrlab3 $(connected_of) $(since $t0) s after the stop"
echo
echo "== hadrlab1: AgPacha, hadrlab3 disconnected"
header; health
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @i int = 0, @t0 datetime2(3) = SYSDATETIME();
WHILE @i < 10
BEGIN
    INSERT m12_registration.dbo.Registration (email)
    SELECT TOP (500) 'disconnected@pachadata.example' FROM sys.all_objects;
    SET @i += 1;
    WAITFOR DELAY '00:00:00.500';
END;
SELECT CONCAT(N'  hadrlab1: ', COUNT(*), N' rows committed in ',
              DATEDIFF(millisecond, @t0, SYSDATETIME()), N' ms while hadrlab3 is disconnected')
FROM m12_registration.dbo.Registration WHERE email = 'disconnected@pachadata.example' AND written_at >= @t0;
SQL
header; health
echo
echo "== hadrlab3: ALTER ENDPOINT hadr_endpoint STATE = STARTED ($(date -u +%T) UTC)"
sql hadrlab3 -Q "ALTER ENDPOINT hadr_endpoint STATE = STARTED;"
t0=$(date +%s.%N)
header "     "
for i in $(seq 0 60); do
    line=$(health "+$i s " | grep hadrlab3)
    echo "$line"
    set -- $line
    [ "$4" = CONNECTED ] && [ "$8" = 0 ] && [ "${11}" = .0 ] && break   # redo_q_kb 0, est_loss_s 0
    sleep 1
done
echo "  hadrlab3 connected and caught up $(since $t0) s after the start of its endpoint"
