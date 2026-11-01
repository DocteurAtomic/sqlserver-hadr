#!/usr/bin/env bash
# ci: skip (it stops the container of hadrlab3, then gives the lab back with setup/install.sh)
# Clip 12.2: the incident the session records. hadrlab3 stops without warning (SHUTDOWN WITH NOWAIT:
# no checkpoint, as after a crash; the container stops with it); hadrlab1 writes for ten
# seconds, sees hadrlab3 DISCONNECTED, then the container starts again and hadrlab3 catches up,
# read on hadrlab1 every second (two minutes at most). Prints the UTC times of each step, which
# 05-read-health.sh then finds in the session and in the error log. Ends with
# setup/install.sh, which checks that the lab is whole again (AgPacha stays). Run after
# 03-health-session.sh. Usage:
#   With Podman: COMPOSE="podman compose" ENGINE=podman ./demos/module_12/04-restart.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
export ENGINE=$engine
running() { [ "$($engine inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
health() { sql hadrlab1 -h -1 < setup/ag-health.sql | cut -d' ' -f2,4- | grep hadrlab3 | sed "s/^/  ${1:-}/"; }
echo "== $(date -u +%T) hadrlab3: SHUTDOWN WITH NOWAIT"
sql hadrlab3 -Q "SHUTDOWN WITH NOWAIT;" >/dev/null 2>&1 || true
for i in $(seq 1 30); do running hadrlab3 || break; sleep 1; done
echo "  $(date -u +%T) the container of hadrlab3 has stopped"
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @i int = 0, @t0 datetime2(3) = SYSDATETIME();
WHILE @i < 20
BEGIN
    INSERT m12_registration.dbo.Registration (email)
    SELECT TOP (500) 'restart@pachadata.example' FROM sys.all_objects;
    SET @i += 1;
    WAITFOR DELAY '00:00:00.500';
END;
SELECT CONCAT(N'  ', CONVERT(char(8), SYSUTCDATETIME(), 108), N' hadrlab1: ', COUNT(*), N' rows committed in ',
              DATEDIFF(millisecond, @t0, SYSDATETIME()), N' ms, hadrlab3 down')
FROM m12_registration.dbo.Registration WHERE email = 'restart@pachadata.example' AND written_at >= @t0;
SQL
health
echo
echo "== $(date -u +%T) hadrlab3: the container starts again"
$engine start hadrlab3 >/dev/null
for i in $(seq 0 120); do
    line=$(health "+$i s " 2>/dev/null || true)
    set -- $line
    if [ "${4:-}" = CONNECTED ] && [ "${8:-}" = 0 ] && [ "${11:-}" = .0 ]; then
        echo "$line"; echo "  $(date -u +%T) hadrlab3 connected and caught up, $i s after its start"; break
    fi
    [ $((i % 5)) = 0 ] && [ -n "$line" ] && echo "$line"
    sleep 1
done
echo
echo "== setup/install.sh, the lab checked whole again"
./setup/install.sh 2>&1 | tail -1
