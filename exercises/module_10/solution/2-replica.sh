#!/usr/bin/env bash
# Exercise of module 10, solution, step 2: hadrlab2 caught up after its resume, then hadrlab3
# removed from AgOps and added back. Without a cluster, hadrlab3 keeps AgOps after the
# REMOVE REPLICA: it is dropped there before the JOIN (otherwise Msg 41106), and the JOIN goes
# through join_ag, which tries again while the group is still being dropped (Msg 41180).
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
wait_ag_database hadrlab1 AgOps ex_operations 120 hadrlab2
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgOps REMOVE REPLICA ON N'hadrlab3';"
sql hadrlab3 -Q "DROP AVAILABILITY GROUP AgOps;"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgOps ADD REPLICA ON N'hadrlab3' WITH (
    ENDPOINT_URL = N'tcp://hadrlab3:5022', AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
    FAILOVER_MODE = MANUAL, SEEDING_MODE = AUTOMATIC);"
join_ag hadrlab3 AgOps
wait_ag_database hadrlab1 AgOps ex_operations 120
