#!/usr/bin/env bash
# Exercise of module 8, one solution. The diagnosis first, then the repair.
# Diagnosis: on hadrlab1, sys.dm_hadr_database_replica_states shows the copies of ex_repair on
# hadrlab2 and hadrlab3 suspended, suspend_reason_desc SUSPEND_FROM_REDO; the error log of each
# secondary says why: CREATE FILE, operating system error 5 (access denied), on
# /var/opt/mssql/data/ex_archive/ex_repair_archive.ndf. The file added on the primary could not
# be created on the secondaries: the folder exists there, but belongs to root.
# Repair: give the folder to the account of SQL Server (mssql) on each secondary, then resume
# the copy on each secondary (a resume sent on the primary would not restart a copy that the
# secondary itself suspended), and read the state again.
# Usage: ./exercises/module_08/solution/2-solution.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
for n in hadrlab2 hadrlab3; do
    $engine exec -u 0 $n chown mssql /var/opt/mssql/data/ex_archive
    sql $n -h -1 -Q "SET NOCOUNT ON; ALTER DATABASE ex_repair SET HADR RESUME;"
done
wait_ag_database hadrlab1 AgRepair ex_repair 120
cat > exercises/module_08/report.md <<'REPORT'
# Diagnosis of AgRepair
Which copies of ex_repair are in trouble, and their state (read on hadrlab1): hadrlab2 and
  hadrlab3, NOT SYNCHRONIZING; the primary, hadrlab1, is SYNCHRONIZED and keeps writing.
What sys.dm_hadr_database_replica_states says about them: is_suspended 1,
  suspend_reason_desc SUSPEND_FROM_REDO (suspended by the secondary itself, during redo).
What the error log of each secondary says: CREATE FILE encountered operating system error
  5 (Access is denied.) on /var/opt/mssql/data/ex_archive/ex_repair_archive.ndf, then data
  movement suspended (SUSPEND_FROM_REDO); ex_repair is SUSPECT on the secondary.
The cause: a file added on the primary is created on every secondary at the same path; the
  folder exists on the secondaries but belongs to root, so SQL Server (mssql) cannot write it.
The repair: chown mssql on the folder on hadrlab2 and hadrlab3, then ALTER DATABASE ex_repair
  SET HADR RESUME on each secondary (on the primary, it changes nothing).
The state after the repair: check.sh exits with 0.
REPORT
echo "exercises/module_08/report.md written."
sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, d.synchronization_state_desc AS sync, d.is_suspended
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
WHERE d.database_id = DB_ID(N'ex_repair') ORDER BY ar.replica_server_name;"
