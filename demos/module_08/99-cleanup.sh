#!/usr/bin/env bash
# Module 8, cleanup of the containers. The demos of module 8 run on the Windows cluster (their
# own cleanup is 99-cleanup-cluster.ps1); on the containers, only the exercise leaves
# something. Gives the lab back as setup/install.sh left it: the group AgRepair removed from
# the three instances (setup/ag-remove.sh), the database ex_repair dropped everywhere with its
# backup and restore history in msdb, the folder ex_archive removed from the data folder of
# each instance, the backup folder removed from the shared volume, and the report of the
# exercise (exercises/module_08/report.md) deleted. evidence/ is not touched.
# Usage: ./demos/module_08/99-cleanup.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash setup/ag-remove.sh AgRepair
for n in $nodes; do
    sql $n -h -1 <<'SQL'
SET NOCOUNT ON;
IF DB_ID(N'ex_repair') IS NOT NULL
BEGIN
    IF DATABASEPROPERTYEX(N'ex_repair', 'Status') = N'ONLINE'
       AND DATABASEPROPERTYEX(N'ex_repair', 'Updateability') = N'READ_WRITE'
        ALTER DATABASE ex_repair SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ex_repair;
    PRINT CONCAT(N'dropped ex_repair on ', @@SERVERNAME);
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
rm -f exercises/module_08/report.md
echo "Module 8 removed from the lab: exercises/module_08/report.md removed, evidence kept."
