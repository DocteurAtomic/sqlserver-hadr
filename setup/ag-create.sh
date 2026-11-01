#!/usr/bin/env bash
# Creates the availability group of the course, without a cluster, as module 3 builds it:
# hadrlab1 primary, hadrlab2 in synchronous commit, hadrlab3 in asynchronous commit, manual
# failover, automatic seeding, secondaries not readable. The databases named after the group
# must be on hadrlab1, in the full recovery model, with a full backup taken (Msg 1475
# otherwise). The secondaries join and are allowed to create the databases, then the script
# waits, at most five minutes per database, until every copy is caught up. Fails when the
# group already exists. For the modules that start from a group: 00-setup.sh calls it.
# Added by module 3. Usage: ./setup/ag-create.sh AgPacha PachadataTraining [database ...]
set -euo pipefail
cd "$(dirname "$0")/.."
. setup/lib.sh
ag=${1:?usage: setup/ag-create.sh <availability group> <database> [database ...]}
shift
[ $# -gt 0 ] || { echo "usage: setup/ag-create.sh <availability group> <database> [database ...]" >&2; exit 2; }
dbs=$(printf '%s, ' "$@"); dbs=${dbs%, }
sql hadrlab1 -h -1 <<SQL
SET NOCOUNT ON;
CREATE AVAILABILITY GROUP $ag
WITH (CLUSTER_TYPE = NONE)
FOR DATABASE $dbs
REPLICA ON
    N'hadrlab1' WITH (ENDPOINT_URL = N'tcp://hadrlab1:5022',
                      AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL,
                      SEEDING_MODE = AUTOMATIC),
    N'hadrlab2' WITH (ENDPOINT_URL = N'tcp://hadrlab2:5022',
                      AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL,
                      SEEDING_MODE = AUTOMATIC),
    N'hadrlab3' WITH (ENDPOINT_URL = N'tcp://hadrlab3:5022',
                      AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL,
                      SEEDING_MODE = AUTOMATIC);
SQL
for n in hadrlab2 hadrlab3; do
    sql $n -h -1 <<SQL
SET NOCOUNT ON;
ALTER AVAILABILITY GROUP $ag JOIN WITH (CLUSTER_TYPE = NONE);
ALTER AVAILABILITY GROUP $ag GRANT CREATE ANY DATABASE;
SQL
done
for db in "$@"; do
    wait_ag_database hadrlab1 "$ag" "$db" 300
done
