#!/usr/bin/env bash
# Module 11, cleanup. Gives the lab back as setup/install.sh left it: the groups AgPacha (the
# demos of clips 11.1 and 11.2), m11_contained (the contained group of clip 11.3) and AgObjects
# (the exercise) removed from the three instances, whatever the roles a failover left them in
# (setup/ag-remove.sh: PachadataTraining stays on hadrlab1 alone, online); then, on each
# instance, the databases of the module (m11_..., the m11_contained_master and
# m11_contained_msdb of the contained group among them) and of its exercise (ex_objects)
# dropped, with their backup and restore history in msdb; the logins m11_app and ex_app; the
# Agent jobs m11_... and ex_..., with their history; and the module's folder on the shared
# volume. The three instances must be running. evidence/ is not touched.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
for ag in AgPacha m11_contained AgObjects; do
    bash setup/ag-remove.sh $ag
done
for n in $nodes; do
    sql $n -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @db sysname, @q nvarchar(max);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE name LIKE N'm11[_]%' OR name = N'ex_objects';
OPEN c;
FETCH c INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF DATABASEPROPERTYEX(@db, 'Status') = N'ONLINE'
       AND DATABASEPROPERTYEX(@db, 'Updateability') = N'READ_WRITE'
    BEGIN
        SET @q = N'ALTER DATABASE ' + QUOTENAME(@db) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
        EXEC (@q);
    END;
    SET @q = N'DROP DATABASE ' + QUOTENAME(@db) + N';';
    EXEC (@q);
    PRINT CONCAT(N'dropped ', @db, N' on ', @@SERVERNAME);
    FETCH c INTO @db;
END;
CLOSE c;
DEALLOCATE c;
DECLARE @ids TABLE (id int PRIMARY KEY);
INSERT @ids SELECT restore_history_id FROM msdb.dbo.restorehistory
WHERE destination_database_name LIKE N'm11[_]%' OR destination_database_name = N'ex_objects';
DELETE msdb.dbo.restorefile WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorefilegroup WHERE restore_history_id IN (SELECT id FROM @ids);
DELETE msdb.dbo.restorehistory WHERE restore_history_id IN (SELECT id FROM @ids);
DECLARE h CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT database_name FROM msdb.dbo.backupset
    WHERE database_name LIKE N'm11[_]%' OR database_name = N'ex_objects';
OPEN h;
FETCH h INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = @db;
    FETCH h INTO @db;
END;
CLOSE h;
DEALLOCATE h;
DECLARE j CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE N'm11[_]%' OR name LIKE N'ex[_]%';
OPEN j;
FETCH j INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = @db, @delete_history = 1, @delete_unused_schedule = 1;
    PRINT CONCAT(N'job ', @db, N' deleted on ', @@SERVERNAME);
    FETCH j INTO @db;
END;
CLOSE j;
DEALLOCATE j;
DECLARE l CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.server_principals WHERE name IN (N'm11_app', N'ex_app');
OPEN l;
FETCH l INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- A session still open with the login would make DROP LOGIN fail (Msg 15434).
    SET @q = N'';
    SELECT @q += N'KILL ' + CAST(session_id AS nvarchar(10)) + N'; '
    FROM sys.dm_exec_sessions WHERE login_name = @db;
    EXEC (@q);
    SET @q = N'DROP LOGIN ' + QUOTENAME(@db) + N';';
    EXEC (@q);
    PRINT CONCAT(N'login ', @db, N' dropped on ', @@SERVERNAME);
    FETCH l INTO @db;
END;
CLOSE l;
DEALLOCATE l;
SQL
done
$engine exec -u 0 hadrlab1 sh -c 'rm -rf /var/opt/mssql/share/m11 /var/opt/mssql/share/ex_objects'
echo "Module 11 removed from the lab."
