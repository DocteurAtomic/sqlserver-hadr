#!/usr/bin/env bash
# Exercise of module 10, starting state. Removes what a previous try left (the group AgOps and
# the database ex_operations, everywhere), creates on hadrlab1 ex_operations in the full
# recovery model with a full backup, then the group AgOps on the three instances as module 3
# builds it (setup/ag-create.sh: hadrlab1 primary, hadrlab2 synchronous, hadrlab3 asynchronous).
# It records in ex_operations.dbo.StartState the identifier that the group gave the replica of
# hadrlab3, then suspends the copy of hadrlab2, as an incident would, and writes 500 rows on
# hadrlab1 while it is suspended. The group AgPacha of the demos is not touched.
# Usage: ./exercises/module_10/1-start.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash setup/ag-remove.sh AgOps >/dev/null
for n in $nodes; do
    sql $n -h -1 -Q "SET NOCOUNT ON; IF DB_ID(N'ex_operations') IS NOT NULL
BEGIN
    IF DATABASEPROPERTYEX(N'ex_operations', 'Status') = N'ONLINE'
       AND DATABASEPROPERTYEX(N'ex_operations', 'Updateability') = N'READ_WRITE'
        ALTER DATABASE ex_operations SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ex_operations;
END;"
done
$engine exec -u 0 hadrlab1 rm -rf /var/opt/mssql/share/ex_operations
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/ex_operations';
CREATE DATABASE ex_operations;
ALTER DATABASE ex_operations SET RECOVERY FULL;
GO
USE ex_operations;
CREATE TABLE dbo.Registration (
    id int IDENTITY PRIMARY KEY,
    batch varchar(40) NOT NULL,
    written_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
INSERT dbo.Registration (batch) SELECT TOP (100) 'start' FROM sys.all_objects;
CREATE TABLE dbo.StartState (replica sysname PRIMARY KEY, replica_id uniqueidentifier NOT NULL);
GO
USE master;
BACKUP DATABASE ex_operations TO DISK = N'/var/opt/mssql/share/ex_operations/ex_operations-start.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
SQL
bash setup/ag-create.sh AgOps ex_operations >/dev/null
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
INSERT ex_operations.dbo.StartState (replica, replica_id)
SELECT ar.replica_server_name, ar.replica_id FROM sys.availability_replicas AS ar
JOIN sys.availability_groups AS g ON g.group_id = ar.group_id
WHERE g.name = N'AgOps' AND ar.replica_server_name = N'hadrlab3';"
wait_ag_database hadrlab1 AgOps ex_operations 120 >/dev/null
sql hadrlab2 -Q "ALTER DATABASE ex_operations SET HADR SUSPEND;"
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
INSERT ex_operations.dbo.Registration (batch) SELECT TOP (500) 'while suspended' FROM sys.all_objects;"
echo "AgOps is ready: hadrlab1 primary, the copy of hadrlab2 suspended, 500 rows written since."
