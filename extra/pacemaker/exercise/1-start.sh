#!/usr/bin/env bash
# Exercise of module 13, starting state. Puts AgPcs back on pc1 if it is elsewhere, removes the
# location constraints a previous move may have left, then creates on pc1 the database ex_pcs
# with its table Visit (one row, written on pc1) and adds it to AgPcs; pc2 receives it by
# automatic seeding. Running it again starts over.
# Usage: ./extra/pacemaker/exercise/1-start.sh     (after ./extra/pacemaker/all.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
. ./lib.sh
. demos/wait.sh
pcs resource clear ag_cluster-clone >/dev/null 2>&1 || true
if [ "$(promoted)" != pc1 ]; then
    pcs resource move ag_cluster-clone pc1 --promoted >/dev/null 2>&1
    pcs resource clear ag_cluster-clone >/dev/null 2>&1 || true
fi
until_true 120 "AgPcs promoted on pc1" role_is pc1 PRIMARY >/dev/null
# A previous ex_pcs leaves the group and the two instances first.
sql pc1 -Q "IF EXISTS (SELECT * FROM sys.availability_databases_cluster WHERE database_name = N'ex_pcs')
    ALTER AVAILABILITY GROUP AgPcs REMOVE DATABASE ex_pcs;" >/dev/null
sleep 2
for n in pc1 pc2; do
    sql $n -Q "IF DB_ID(N'ex_pcs') IS NOT NULL BEGIN
        IF DATABASEPROPERTYEX(N'ex_pcs', 'Status') = 'ONLINE' AND DATABASEPROPERTYEX(N'ex_pcs', 'Updateability') = 'READ_WRITE'
            ALTER DATABASE ex_pcs SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        DROP DATABASE ex_pcs; END;" >/dev/null
done
sql pc1 >/dev/null <<'SQL'
SET NOCOUNT ON;
CREATE DATABASE ex_pcs;
ALTER DATABASE ex_pcs SET RECOVERY FULL;
GO
-- server: the instance that was primary when the row was committed.
CREATE TABLE ex_pcs.dbo.Visit (
    id int IDENTITY PRIMARY KEY,
    server sysname NOT NULL DEFAULT @@SERVERNAME,
    visited datetime2(0) NOT NULL DEFAULT SYSDATETIME());
INSERT ex_pcs.dbo.Visit DEFAULT VALUES;
BACKUP DATABASE ex_pcs TO DISK = N'/var/opt/mssql/data/ex_pcs.bak' WITH INIT;
GO
ALTER AVAILABILITY GROUP AgPcs ADD DATABASE ex_pcs;
SQL
until_true 120 "ex_pcs SYNCHRONIZED on pc2" bash -c "[ \"\$(podman exec -i pc2 /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U sa -C -h -1 -W -Q \"SET NOCOUNT ON; SELECT synchronization_state_desc FROM sys.dm_hadr_database_replica_states WHERE is_local = 1 AND database_id = DB_ID(N'ex_pcs')\" | tr -d ' \r')\" = SYNCHRONIZED ]"
echo "ex_pcs is in AgPcs, primary on pc1, synchronized on pc2. Over to you: read README.md."
