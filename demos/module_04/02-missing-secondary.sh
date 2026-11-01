#!/usr/bin/env bash
# ci: skip (it stops the container of hadrlab2, then gives the lab back with setup/install.sh)
# Clip 4.2: the secondary that is missing. hadrlab2, the synchronous secondary, is shut down
# cleanly (SHUTDOWN, as setup/stop.sh does: "docker stop" would kill SQL Server). On hadrlab1,
# the primary: what the group says of hadrlab2, then a load of about 300 MB written in
# m04_registration, which commits without waiting for anyone, then a log backup that frees
# nothing: log_reuse_wait_desc is AVAILABILITY_REPLICA. Then hadrlab2 starts again and catches
# up, read on the primary every second (at most three minutes), and the next log backup frees
# the log. Appends the measures to evidence/module_04.md. Ends with setup/install.sh, which
# checks that the lab is whole again (AgPacha stays). Run after 00-setup.sh.
# Usage: ./demos/module_04/02-missing-secondary.sh
#   With Podman: COMPOSE="podman compose" ENGINE=podman ./demos/module_04/02-missing-secondary.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
export ENGINE=$engine
running() { [ "$($engine inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
log_state() {  # one line: the log of m04_registration on hadrlab1
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'log of m04_registration: ', FORMAT(u.used_log_space_in_bytes / 1048576.0, N'0.0'), N' MB used of ',
              FORMAT(u.total_log_size_in_bytes / 1048576.0, N'0.0'), N' MB, log_reuse_wait_desc ', d.log_reuse_wait_desc)
FROM sys.databases AS d CROSS APPLY m04_registration.sys.dm_db_log_space_usage AS u
WHERE d.name = N'm04_registration';"
}
replicas() {  # the secondaries of m04_registration, seen from hadrlab1
    sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, ar.availability_mode_desc AS mode,
       rs.connected_state_desc AS connected, d.synchronization_state_desc AS sync,
       d.is_commit_participant AS commit_participant,
       ISNULL(CAST(d.log_send_queue_size AS varchar(20)), 'NULL') AS send_queue_kb,
       ISNULL(CAST(d.redo_queue_size AS varchar(20)), 'NULL') AS redo_queue_kb
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
WHERE d.database_id = DB_ID(N'm04_registration') AND d.is_local = 0
ORDER BY ar.replica_server_name;"
}
backup_log() {  # one log backup of m04_registration, to the shared volume
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; BACKUP LOG m04_registration
        TO DISK = N'/var/opt/mssql/share/m04/m04_registration-$(date +%H%M%S%N).trn' WITH INIT, COMPRESSION;" \
        | grep 'BACKUP LOG' || true
}
reuse_wait() {
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT log_reuse_wait_desc FROM sys.databases WHERE name = N'm04_registration';" \
        | tr -d '[:space:]'
}
release_log() {  # a log backup every 5 seconds, at most a number of seconds, until the log is
                 # no longer held by a replica; the secondaries report how far they have redone
                 # a few seconds late, so one backup is not enough to conclude
    local limit=$1 t=$(date +%s) n=0 w
    while :; do
        backup_log >/dev/null; n=$((n + 1))
        w=$(reuse_wait)
        if [ "$w" != AVAILABILITY_REPLICA ] || [ $(( $(date +%s) - t )) -ge "$limit" ]; then break; fi
        sleep 5
    done
    echo "$n log backups in $(( $(date +%s) - t )) s, log_reuse_wait_desc now $w"
}
echo "== hadrlab1, before: log backups until the replicas release the log (at most 2 minutes)"
release_log 120
log_state
echo
echo "== hadrlab2: SHUTDOWN"
t=$(date +%s.%N)
sql hadrlab2 -Q "SHUTDOWN;" >/dev/null 2>&1 || true
for i in $(seq 1 60); do running hadrlab2 || break; sleep 1; done
if running hadrlab2; then echo "hadrlab2 still runs 60 s after SHUTDOWN" >&2; exit 1; fi
echo "hadrlab2 stopped in $(awk -v s=$t -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }') s"
# The primary sees the connection close a few seconds later: wait for it, at most a minute.
for i in $(seq 1 60); do
    c=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT rs.connected_state_desc
        FROM sys.availability_replicas AS ar JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
        WHERE ar.replica_server_name = N'hadrlab2';" | tr -d '[:space:]')
    [ "$c" = DISCONNECTED ] && break
    sleep 1
done
[ "$c" = DISCONNECTED ] || { echo "hadrlab1 still sees hadrlab2 connected after a minute" >&2; exit 1; }
echo "hadrlab1 sees hadrlab2 DISCONNECTED $(awk -v s=$t -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }') s after the SHUTDOWN"
echo
echo "== hadrlab1, the secondaries without hadrlab2"
replicas
echo
echo "== hadrlab1, a load of about 300 MB in m04_registration"
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @t0 datetime2(3) = SYSDATETIME();
CREATE TABLE m04_registration.dbo.Attachment (id int IDENTITY PRIMARY KEY, body char(4000) NOT NULL);
INSERT m04_registration.dbo.Attachment (body)
SELECT TOP (75000) REPLICATE('x', 4000) FROM sys.all_columns AS a CROSS JOIN sys.all_columns AS b;
SELECT CONCAT(COUNT(*), N' rows committed in ', DATEDIFF(millisecond, @t0, SYSDATETIME()), N' ms')
FROM m04_registration.dbo.Attachment;
SQL
echo "Log backups while hadrlab2 is stopped, for 30 seconds:"
release_log 30
log_state
replicas
load_mb=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT FORMAT(used_log_space_in_bytes / 1048576.0, N'0') FROM m04_registration.sys.dm_db_log_space_usage;" | tr -d '[:space:]')
echo
echo "== hadrlab2: start, then the catch-up read on hadrlab1 every second"
t=$(date +%s.%N)
$engine start hadrlab2 >/dev/null
last=""
done_at=""
for i in $(seq 1 180); do
    now=$(sql hadrlab1 -h -1 -s '|' -Q "SET NOCOUNT ON;
USE m04_registration; CHECKPOINT;
SELECT rs.connected_state_desc, ISNULL(d.synchronization_state_desc, N'-'),
       ISNULL(CAST(d.log_send_queue_size AS varchar(20)), 'NULL'), ISNULL(CAST(d.redo_queue_size AS varchar(20)), 'NULL')
FROM sys.availability_replicas AS ar
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
LEFT JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id AND d.database_id = DB_ID(N'm04_registration')
WHERE ar.replica_server_name = N'hadrlab2';" 2>/dev/null | grep -v 'Changed database' | tr -d '\r' || true)
    el=$(awk -v s=$t -v e=$(date +%s.%N) 'BEGIN { printf "%.0f", e - s }')
    if [ -n "$now" ] && [ "$now" != "$last" ]; then echo "+${el} s  $now  (connected|sync|send_queue_kb|redo_queue_kb)"; last=$now; fi
    case $now in "CONNECTED|SYNCHRONIZED|0|0") done_at=$el; break ;; esac
    sleep 1
done
if [ -z "$done_at" ]; then echo "hadrlab2 has not caught up within three minutes" >&2; exit 1; fi
echo "hadrlab2 caught up ${done_at} s after its start"
echo
echo "== hadrlab1, after: log backups until the replicas release the log (at most 2 minutes)"
t=$(date +%s)
release_log 120
log_state
[ "$(reuse_wait)" != AVAILABILITY_REPLICA ] || { echo "the log is still held two minutes after the catch-up" >&2; exit 1; }
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 4, hadrlab2 (synchronous secondary) shut down: the primary kept committing alone, a log backup after a load left ${load_mb} MB of log used in m04_registration (log_reuse_wait_desc AVAILABILITY_REPLICA); hadrlab2 restarted and caught up ${done_at} s after its start, three containers on one host" >> evidence/module_04.md
echo
echo "== setup/install.sh, the lab checked whole again"
./setup/install.sh 2>&1 | tail -1
