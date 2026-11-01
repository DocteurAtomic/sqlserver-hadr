#!/usr/bin/env bash
# Clip 5.2: the read-write redirection, without a listener. Each replica gets a
# READ_WRITE_ROUTING_URL (its name and port 1433 in the lab network): a connection that
# reaches a secondary without the read-only intent is sent to the primary, whichever it is.
# Read from the sqlcmd of the container hadrlab2, inside the lab network (lands_on): with
# hadrlab3 in READ_ONLY, the connection is still refused; with hadrlab3 in ALL, it lands on
# hadrlab1, in READ_WRITE; with -K ReadOnly it stays on hadrlab3. hadrlab2, still
# ALLOW_CONNECTIONS = NO, refuses it. hadrlab3 is put back in READ_ONLY at the end, the URLs
# stay. Run after 01-readable.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
allow() {  # sets ALLOW_CONNECTIONS on hadrlab3, and waits until hadrlab3 reads it (at most 30 s)
    sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = $1));"
    for i in $(seq 1 30); do
        [ "$(sql hadrlab3 -h -1 -Q "SET NOCOUNT ON; SELECT secondary_role_allow_connections_desc FROM sys.availability_replicas WHERE replica_server_name = N'hadrlab3';" | tr -d '[:space:]')" = "$1" ] && { echo "  hadrlab3: ALLOW_CONNECTIONS = $1"; return; }
        sleep 1
    done
    echo "hadrlab3 does not see ALLOW_CONNECTIONS = $1 after 30 seconds" >&2; exit 1
}
try() { printf '  %-34s -> %s\n' "$*" "$(lands_on hadrlab2 "$@")"; }
echo "== hadrlab1: a READ_WRITE_ROUTING_URL for each replica"
sql hadrlab1 -Q "SET NOCOUNT ON;
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab1' WITH (PRIMARY_ROLE (READ_WRITE_ROUTING_URL = N'tcp://hadrlab1:1433'));
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab2' WITH (PRIMARY_ROLE (READ_WRITE_ROUTING_URL = N'tcp://hadrlab2:1433'));
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (PRIMARY_ROLE (READ_WRITE_ROUTING_URL = N'tcp://hadrlab3:1433'));
SELECT replica_server_name AS replica, secondary_role_allow_connections_desc AS secondary_allow, read_write_routing_url
FROM sys.availability_replicas ORDER BY replica_server_name;"
echo
echo "== from the container hadrlab2, hadrlab3 in READ_ONLY"
allow READ_ONLY
try hadrlab3 -d m05_reports
echo
echo "== from the container hadrlab2, hadrlab3 in ALL"
allow ALL
try hadrlab3 -d m05_reports
try hadrlab3 -d m05_reports -K ReadOnly
try hadrlab3 -d master
echo
echo "== from the container hadrlab3, hadrlab2 (ALLOW_CONNECTIONS = NO)"
printf '  %-34s -> %s\n' "hadrlab2 -d m05_reports" "$(lands_on hadrlab3 hadrlab2 -d m05_reports)"
echo
allow READ_ONLY
