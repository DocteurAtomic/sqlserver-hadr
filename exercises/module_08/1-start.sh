#!/usr/bin/env bash
# Exercise of module 8, starting state. Removes what a previous attempt left (the group
# AgRepair and the database ex_repair on the three instances, with their history and the
# folder ex_archive), then creates on hadrlab1 the database ex_repair, in the full recovery
# model, with a full backup, and the group AgRepair, without a cluster, as module 3 builds
# AgPacha (setup/ag-create.sh): hadrlab2 in synchronous commit, hadrlab3 in asynchronous
# commit. Once both copies are caught up, a change made on the primary breaks the two
# secondaries, then 200 rows are written on hadrlab1. What broke is for you to find: the
# script does not say it. It also writes exercises/module_08/report.md, the report to fill in
# (ignored by git). AgPacha is not touched. Run it again to start over.
# Usage: ./exercises/module_08/1-start.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash setup/ag-remove.sh AgRepair > /dev/null
for n in $nodes; do
    sql $n -h -1 <<'SQL'
SET NOCOUNT ON;
IF DB_ID(N'ex_repair') IS NOT NULL
BEGIN
    IF DATABASEPROPERTYEX(N'ex_repair', 'Status') = N'ONLINE'
       AND DATABASEPROPERTYEX(N'ex_repair', 'Updateability') = N'READ_WRITE'
        ALTER DATABASE ex_repair SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ex_repair;
END;
DECLARE @ids TABLE (id int PRIMARY KEY);
INSERT @ids SELECT restore_history_id FROM msdb.dbo.restorehistory WHERE destination_database_name = N'ex_repair';
DELETE msdb.dbo.restorefile WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorefilegroup WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorehistory WHERE restore_history_id IN (SELECT id FROM @ids);
IF EXISTS (SELECT * FROM msdb.dbo.backupset WHERE database_name = N'ex_repair')
    EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'ex_repair';
SQL
    $engine exec -u 0 $n rm -rf /var/opt/mssql/data/ex_archive
done
$engine exec -u 0 hadrlab1 rm -rf /var/opt/mssql/share/ex_repair
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
CREATE DATABASE ex_repair;
ALTER DATABASE ex_repair SET RECOVERY FULL;
GO
USE ex_repair;
CREATE TABLE dbo.Registration (
    id int IDENTITY PRIMARY KEY,
    batch varchar(20) NOT NULL,
    email varchar(100) NOT NULL,
    written_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
GO
USE master;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/ex_repair';
BACKUP DATABASE ex_repair TO DISK = N'/var/opt/mssql/share/ex_repair/ex_repair-full.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
SQL
bash setup/ag-create.sh AgRepair ex_repair
# The change: a file added to the database, in a folder that the secondaries already have,
# owned by root (an administrator made it by hand, before the change).
for n in hadrlab2 hadrlab3; do
    $engine exec -u 0 $n sh -c 'mkdir -p /var/opt/mssql/data/ex_archive && chown root:root /var/opt/mssql/data/ex_archive && chmod 755 /var/opt/mssql/data/ex_archive'
done
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/data/ex_archive';
ALTER DATABASE ex_repair ADD FILEGROUP archive;
ALTER DATABASE ex_repair ADD FILE (NAME = ex_repair_archive,
    FILENAME = N'/var/opt/mssql/data/ex_archive/ex_repair_archive.ndf', SIZE = 8MB) TO FILEGROUP archive;
GO
INSERT ex_repair.dbo.Registration (batch, email)
SELECT TOP (200) 'after the change', CONCAT('user', ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), '@pachadata.example')
FROM sys.all_objects;
SQL
sleep 5
f=exercises/module_08/report.md
cat > "$f" <<'REPORT'
# Diagnosis of AgRepair
Which copies of ex_repair are in trouble, and their state (read on hadrlab1):
What sys.dm_hadr_database_replica_states says about them (is_suspended, suspend_reason_desc):
What the error log of each secondary says (time, error, file):
The cause:
The repair, in the order you made it:
The state after the repair (check.sh):
REPORT
echo "$f written: the report to fill in."
echo "AgRepair is ready on hadrlab1, hadrlab2 and hadrlab3; something is wrong with it. Read exercises/module_08/README.md."
