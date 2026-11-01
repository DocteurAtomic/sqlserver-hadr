#!/usr/bin/env bash
# Exercise of module 2, starting state. Removes what a previous attempt left (the log shipping
# of ex_logship on hadrlab1 and hadrlab3 with its jobs, the databases, the files), then
# creates on hadrlab1 the database ex_logship in the full recovery model, without any backup:
# a table dbo.Registration of 100 rows, and the empty folders of the shared volume
# (/var/opt/mssql/share/ex_logship for the full backup, /var/opt/mssql/share/logship/ex_logship
# for the log backups). Run it again to start over.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
for n in hadrlab1 hadrlab3; do
    sql $n -v DB='ex[_]logship' < setup/logship-remove.sql
    sql $n <<'SQL'
SET NOCOUNT ON;
IF DB_ID(N'ex_logship') IS NOT NULL
BEGIN
    IF DATABASEPROPERTYEX(N'ex_logship', 'Status') = N'ONLINE'
       AND DATABASEPROPERTYEX(N'ex_logship', 'IsInStandBy') = 0
        ALTER DATABASE ex_logship SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ex_logship;
END;
IF EXISTS (SELECT * FROM msdb.dbo.backupset WHERE database_name = N'ex_logship')
   OR EXISTS (SELECT * FROM msdb.dbo.restorehistory WHERE destination_database_name = N'ex_logship')
    EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'ex_logship';
SQL
    $engine exec -u 0 $n sh -c 'rm -rf /var/opt/mssql/logship-copy/ex_logship; rm -f /var/opt/mssql/data/ex_logship_*.tuf'
done
$engine exec -u 0 hadrlab1 rm -rf /var/opt/mssql/share/ex_logship /var/opt/mssql/share/logship/ex_logship \
    /var/opt/mssql/share/logship/ex_logship_tail.trn
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
CREATE DATABASE ex_logship;
ALTER DATABASE ex_logship SET RECOVERY FULL;
GO
USE ex_logship;
CREATE TABLE dbo.Registration (
    id int IDENTITY PRIMARY KEY,
    label varchar(50) NOT NULL,
    written_at datetime2(3) NOT NULL DEFAULT SYSDATETIME());
INSERT dbo.Registration (label)
SELECT TOP (100) CONCAT('start ', ROW_NUMBER() OVER (ORDER BY (SELECT NULL)))
FROM sys.all_objects;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/ex_logship';
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/logship/ex_logship';
SELECT DB_NAME() AS database_name, COUNT(*) AS registrations FROM dbo.Registration;
GO
SQL
