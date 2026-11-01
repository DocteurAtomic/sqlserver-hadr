#!/usr/bin/env bash
# Clip 6.2: the listener after a failover, and the failover as a script. On hadrlab1, the
# listener agpacha-lsn, port 1433, on the address of hadrlab1 in the lab network, read in the
# container (module 5). From the container hadrlab3, a connection to that address with the
# database m06_registration lands on hadrlab1, READ_WRITE. Then setup/ag-failover.sh AgPacha
# hadrlab2, the sequence of 02-planned.sh in one script, timed. The listener has not moved:
# hadrlab2 lists it on the address of hadrlab1, and the same connection lands on hadrlab1, now
# a secondary closed to connections. On hadrlab2, the listener is removed and created again on
# the address of hadrlab2 (step 8 of the Learn page), and the connection lands on hadrlab2.
# Then the way back: setup/ag-failover.sh AgPacha hadrlab1, the listener moved back. Appends
# the two durations to evidence/module_06.md. Leaves hadrlab1 primary, with the listener on its
# address. Run after 03-learn-as-written.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
land() { lands_on hadrlab3 "$@" | sed 's/\. .*/./'; }  # where a connection from hadrlab3 lands, first sentence
addr() { $engine exec "$1" hostname -I | awk '{print $1}'; }
listener_on() {  # creates the listener on the address of an instance, which must be the primary
    local n=$1 ip
    ip=$(addr $n)
    sql $n -Q "SET NOCOUNT ON;
IF EXISTS (SELECT * FROM sys.availability_group_listeners WHERE dns_name = N'agpacha-lsn')
    ALTER AVAILABILITY GROUP AgPacha REMOVE LISTENER N'agpacha-lsn';
ALTER AVAILABILITY GROUP AgPacha ADD LISTENER N'agpacha-lsn' (WITH IP ((N'$ip', N'255.255.255.0')), PORT = 1433);"
    echo "  $n: listener agpacha-lsn on $ip, port 1433"
}
listener() {  # the listener as an instance lists it
    sql $1 -Q "SET NOCOUNT ON;
SELECT @@SERVERNAME AS listed_by, l.dns_name, l.port, a.ip_address, a.state_desc
FROM sys.availability_group_listeners AS l
JOIN sys.availability_group_listener_ip_addresses AS a ON a.listener_id = l.listener_id;"
}
ip1=$(addr hadrlab1); ip2=$(addr hadrlab2)
echo "== the addresses in the lab network, read in the containers: hadrlab1 $ip1, hadrlab2 $ip2"
echo "== hadrlab1"
listener_on hadrlab1
printf '  from hadrlab3, %s -d m06_registration -> %s\n' "$ip1" "$(land "$ip1" -d m06_registration)"
echo
echo "== setup/ag-failover.sh AgPacha hadrlab2"
out=$(bash setup/ag-failover.sh AgPacha hadrlab2)
echo "$out" | sed 's/^/  /'
d1=$(echo "$out" | tail -1 | grep -o '[0-9.]* s$')
echo
echo "== hadrlab2, the new primary"
listener hadrlab2
printf '  from hadrlab3, %s -d m06_registration -> %s\n' "$ip1" "$(land "$ip1" -d m06_registration)"
listener_on hadrlab2
listener hadrlab2
printf '  from hadrlab3, %s -d m06_registration -> %s\n' "$ip2" "$(land "$ip2" -d m06_registration)"
echo
echo "== setup/ag-failover.sh AgPacha hadrlab1, and the listener back on hadrlab1"
out=$(bash setup/ag-failover.sh AgPacha hadrlab1)
echo "$out" | sed 's/^/  /'
d2=$(echo "$out" | tail -1 | grep -o '[0-9.]* s$')
listener_on hadrlab1
printf '  from hadrlab3, %s -d m06_registration -> %s\n' "$ip1" "$(land "$ip1" -d m06_registration)"
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 6, planned failover without a cluster by setup/ag-failover.sh, three replicas: hadrlab1 to hadrlab2 in $d1, back in $d2 (writes refused for that time, nothing lost, the listener moved by hand afterwards); three containers on one host" >> evidence/module_06.md
