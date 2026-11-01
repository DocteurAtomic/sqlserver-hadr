#!/usr/bin/env bash
# Clip 5.2: the read-only routing, which needs a listener. On hadrlab1: a READ_ONLY_ROUTING_URL
# for hadrlab3 and hadrlab2, given in two statements, since ALLOW_CONNECTIONS and the URL in
# the same MODIFY REPLICA are refused (Msg 10786, shown first), then a READ_ONLY_ROUTING_LIST
# for the primary role of hadrlab1. Without a listener, a connection to hadrlab1 with
# -K ReadOnly stays there. Then the listener agpacha-lsn, port 1433, on the address of
# hadrlab1 in the lab network, read in the container (hostname -I), never written in the
# script: it changes with each lab. A group without a cluster does not move it, does not check
# the mask, and does not register any name; the connections reach it by that address, or by
# the name hadrlab1, which resolves to it. From the container hadrlab3: -K ReadOnly with
# m05_reports is routed to hadrlab3; without a database of the group (master), or without the
# intent, it stays on hadrlab1; through 127.0.0.1 inside hadrlab1, which is not the address
# of the listener, it is not routed either. One listener for the group: modules 6 and later
# recreate it after a failover. Run after 04-read-write-routing.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
try() { printf '  %-44s -> %s\n' "$*" "$(lands_on hadrlab3 "$@")"; }
echo "== hadrlab1: ALLOW_CONNECTIONS and READ_ONLY_ROUTING_URL in one statement"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3'
    WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY, READ_ONLY_ROUTING_URL = N'tcp://hadrlab3:1433'));" 2>&1 || true
echo
echo "== hadrlab1: the URLs one by one, then the routing list of hadrlab1"
sql hadrlab1 -Q "SET NOCOUNT ON;
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (SECONDARY_ROLE (READ_ONLY_ROUTING_URL = N'tcp://hadrlab3:1433'));
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab2' WITH (SECONDARY_ROLE (READ_ONLY_ROUTING_URL = N'tcp://hadrlab2:1433'));
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab1' WITH (PRIMARY_ROLE (READ_ONLY_ROUTING_LIST = (N'hadrlab3', N'hadrlab2')));
SELECT ar.replica_server_name AS when_primary, rl.routing_priority AS priority, ar2.replica_server_name AS routed_to,
       ar2.secondary_role_allow_connections_desc AS its_allow, ar2.read_only_routing_url
FROM sys.availability_read_only_routing_lists AS rl
JOIN sys.availability_replicas AS ar ON ar.replica_id = rl.replica_id
JOIN sys.availability_replicas AS ar2 ON ar2.replica_id = rl.read_only_replica_id
ORDER BY rl.routing_priority;"
echo
echo "== from the container hadrlab3, no listener"
try hadrlab1 -d m05_reports -K ReadOnly
echo
ip=$($engine exec hadrlab1 hostname -I | awk '{print $1}')
echo "== hadrlab1: its address in the lab network, read in the container: $ip"
echo "== hadrlab1: the listener agpacha-lsn on $ip, port 1433"
sql hadrlab1 -Q "SET NOCOUNT ON;
ALTER AVAILABILITY GROUP AgPacha ADD LISTENER N'agpacha-lsn' (WITH IP ((N'$ip', N'255.255.255.0')), PORT = 1433);
SELECT l.dns_name, l.port, a.ip_address, a.state_desc
FROM sys.availability_group_listeners AS l
JOIN sys.availability_group_listener_ip_addresses AS a ON a.listener_id = l.listener_id;
SELECT ip_address, port, state_desc FROM sys.dm_tcp_listener_states WHERE type_desc = N'TSQL' AND ip_address = N'$ip';"
echo
echo "== from the container hadrlab3, through the listener"
try hadrlab1 -d m05_reports -K ReadOnly
try "$ip" -d m05_reports -K ReadOnly
try hadrlab1 -K ReadOnly
try hadrlab1 -d m05_reports
echo
echo "== from the container hadrlab1 itself"
printf '  %-44s -> %s\n' "127.0.0.1 -d m05_reports -K ReadOnly" "$(lands_on hadrlab1 127.0.0.1 -d m05_reports -K ReadOnly)"
