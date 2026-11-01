-- instance: hadrlab1
-- Clip 1.1: the RPO and the RTO that the instance's history allows today. Run after
-- 00-setup.sh. Reads msdb and the error log, changes nothing.
USE msdb;
SET NOCOUNT ON;
GO
-- 1. For each database: its recovery model, its last backups taken on this server, and the
--    seconds since the last backup that holds its log. If the instance were lost now, with a
--    log that cannot be read any more, everything written since then would be lost.
SELECT d.name,
       d.recovery_model_desc AS recovery_model,
       MAX(IIF(b.type = 'D', b.backup_finish_date, NULL)) AS last_full,
       MAX(IIF(b.type = 'I', b.backup_finish_date, NULL)) AS last_diff,
       MAX(IIF(b.type = 'L', b.backup_finish_date, NULL)) AS last_log,
       DATEDIFF(second, MAX(b.backup_finish_date), SYSDATETIME()) AS seconds_exposed
FROM sys.databases AS d
LEFT JOIN dbo.backupset AS b
       ON b.database_name = d.name AND b.server_name = @@SERVERNAME AND b.is_copy_only = 0
WHERE d.name IN (N'PachadataTraining', N'm01_registration')
GROUP BY d.name, d.recovery_model_desc
ORDER BY d.name;
GO
-- 2. The chain of m01_registration: what a restore elsewhere would read, in order, and the
--    interval between two backups that hold the log, which is the RPO of the schedule.
SELECT b.type,
       b.backup_start_date,
       b.backup_finish_date,
       DATEDIFF(second, LAG(b.backup_finish_date) OVER (ORDER BY b.backup_finish_date),
                b.backup_finish_date) AS seconds_since_previous,
       CAST(b.compressed_backup_size / 1048576.0 AS decimal(9, 1)) AS compressed_mb,
       f.physical_device_name
FROM dbo.backupset AS b
JOIN dbo.backupmediafamily AS f ON f.media_set_id = b.media_set_id
WHERE b.database_name = N'm01_registration' AND b.server_name = @@SERVERNAME
ORDER BY b.backup_finish_date;
GO
-- 3. The restores this instance has done, and the backup each one read: the restore of
--    PachadataTraining by setup/install.sh comes from a backup taken on another server.
SELECT r.destination_database_name AS database_name,
       r.restore_date,
       r.restore_type,
       b.server_name AS backup_taken_on,
       CAST(b.backup_size / 1048576.0 AS decimal(9, 1)) AS backup_mb
FROM dbo.restorehistory AS r
JOIN dbo.backupset AS b ON b.backup_set_id = r.backup_set_id
WHERE r.destination_database_name IN (N'PachadataTraining', N'm01_registration')
ORDER BY r.restore_date;
GO
-- 4. How long the last restore of each database took: msdb does not keep it, the error log
--    does, in the line "successfully processed" written with the "Restore is complete" of
--    the database. The error log starts anew at each start of the instance, and the six
--    previous ones are kept: the loop reads them all.
CREATE TABLE #log (LogDate datetime2(3), ProcessInfo nvarchar(50), Text nvarchar(max));
CREATE TABLE #archives (archive int, log_date nvarchar(30), size_bytes bigint);
INSERT #archives EXEC sys.xp_enumerrorlogs;
DECLARE @a int = (SELECT MAX(archive) FROM #archives);
WHILE @a >= 0
BEGIN
    INSERT #log EXEC sys.xp_readerrorlog @a, 1, N'Restore is complete on database';
    INSERT #log EXEC sys.xp_readerrorlog @a, 1, N'RESTORE DATABASE successfully processed';
    SET @a -= 1;
END;
WITH done AS (
    SELECT d.name, MAX(l.LogDate) AS LogDate
    FROM (VALUES (N'PachadataTraining'), (N'm01_registration')) AS d (name)
    JOIN #log AS l ON l.Text LIKE N'Restore is complete on database ''' + d.name + N'''%'
    GROUP BY d.name)
SELECT done.name AS database_name, l.LogDate, l.Text
FROM done
JOIN #log AS l ON l.Text LIKE N'RESTORE DATABASE successfully processed%'
              AND ABS(DATEDIFF(millisecond, done.LogDate, l.LogDate)) < 200
ORDER BY l.LogDate;
DROP TABLE #log, #archives;
GO
