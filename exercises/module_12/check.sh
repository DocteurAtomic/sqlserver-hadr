#!/usr/bin/env bash
# Exercise of module 12: checks that the group AgHealth is healthy again, read on hadrlab1, its
# primary. It reads the state, never the commands:
#   - hadrlab1 is the primary of AgHealth, and the group's health is HEALTHY;
#   - each secondary replica, hadrlab2 and hadrlab3, is CONNECTED;
#   - each copy of ex_health is joined, not suspended, SYNCHRONIZED on the synchronous replica,
#     SYNCHRONIZING or SYNCHRONIZED on the asynchronous one, and the primary knows its send queue
#     (not NULL).
# Exits with 0 when everything holds, with 1 otherwise, saying what is wrong.
# Usage: ./exercises/module_12/check.sh     (with Podman: ENGINE=podman ...)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
fail=0
ok() { echo "ok   $*"; }
ko() { echo "FAIL $*"; fail=1; }
q() { sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; $1" 2>/dev/null | tr -d '\r' | sed 's/ *$//' | grep -v '^$'; }
role=$(q "SELECT ISNULL((SELECT rs.role_desc FROM sys.availability_groups AS g
    JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.group_id = g.group_id AND rs.is_local = 1
    WHERE g.name = N'AgHealth'), N'no AgHealth');")
if [ "$role" != PRIMARY ]; then
    echo "FAIL hadrlab1: AgHealth is '${role:-no answer}', PRIMARY expected (run exercises/module_12/1-start.sh to start over)"
    exit 1
fi
health=$(q "SELECT s.synchronization_health_desc FROM sys.dm_hadr_availability_group_states AS s
    JOIN sys.availability_groups AS g ON g.group_id = s.group_id WHERE g.name = N'AgHealth';")
[ "$health" = HEALTHY ] && ok "AgHealth: HEALTHY, read on hadrlab1" || ko "AgHealth: $health, read on hadrlab1"
for n in hadrlab2 hadrlab3; do
    line=$(q "SELECT CONCAT(ISNULL(rs.connected_state_desc, N'?'), N'|', ar.endpoint_url, N'|', ar.availability_mode_desc, N'|',
        ISNULL(d.synchronization_state_desc, N'not joined'), N'|', ISNULL(d.suspend_reason_desc, N'-'), N'|',
        ISNULL(CAST(d.log_send_queue_size AS nvarchar(20)), N'NULL'))
        FROM sys.availability_groups AS g JOIN sys.availability_replicas AS ar ON ar.group_id = g.group_id
        LEFT JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
        LEFT JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id AND d.database_id = DB_ID(N'ex_health')
        WHERE g.name = N'AgHealth' AND ar.replica_server_name = N'$n';")
    if [ -z "$line" ]; then ko "$n: not a replica of AgHealth"; continue; fi
    IFS='|' read -r connected _url mode sync suspended queue <<< "$line"
    [ "$connected" = CONNECTED ] && ok "$n: CONNECTED" || ko "$n: $connected, read on hadrlab1"
    if [ "$suspended" != - ]; then ko "$n: the copy of ex_health is suspended ($suspended)"
    elif [ "$mode" = SYNCHRONOUS_COMMIT ] && [ "$sync" != SYNCHRONIZED ]; then ko "$n: the copy of ex_health is $sync, SYNCHRONIZED expected (synchronous commit)"
    elif [ "$mode" = ASYNCHRONOUS_COMMIT ] && [ "$sync" != SYNCHRONIZING ] && [ "$sync" != SYNCHRONIZED ]; then ko "$n: the copy of ex_health is $sync, SYNCHRONIZING expected (asynchronous commit)"
    else ok "$n: the copy of ex_health is $sync"; fi
    [ "$queue" != NULL ] && ok "$n: send queue known ($queue KB)" || ko "$n: send queue unknown (NULL): the primary does not know what it has not sent"
done
if [ $fail = 1 ]; then echo "AgHealth is not healthy yet."; exit 1; fi
echo "AgHealth is healthy: both secondaries connected, their copies of ex_health caught up."
