-- ci: skip (Windows cluster of the course, not the containers)
-- Runs on the primary replica (SQL01), in sqlcmd. Module 8, clip 8.4: writes into
-- m08_registrations in batches of about 16 MB, and after each batch prints the size of the log
-- file, the free space of the volume M: and the state of the copy on the secondary. M: is a
-- 100 MB disk on SQL02 and a 300 MB disk on SQL01: the secondary fills first.
-- Usage: sqlcmd -S . -E -C -i 11-fill.sql -v BATCHES=5
SET NOCOUNT ON;
USE m08_registrations;
IF OBJECT_ID(N'dbo.filler') IS NULL
    CREATE TABLE dbo.filler (id int IDENTITY PRIMARY KEY, pad char(4000) NOT NULL DEFAULT 'x');
DECLARE @b int = 0;
WHILE @b < $(BATCHES)
BEGIN
    SET @b += 1;
    BEGIN TRY
        INSERT dbo.filler (pad) SELECT TOP (4000) 'x' FROM sys.all_columns AS a CROSS JOIN sys.all_columns AS b;
    END TRY
    BEGIN CATCH
        PRINT CONCAT(CONVERT(varchar(12), SYSUTCDATETIME(), 114), ' batch ', @b, ': Msg ', ERROR_NUMBER(), ' ', LEFT(ERROR_MESSAGE(), 150));
    END CATCH;
    SELECT CONVERT(varchar(12), SYSUTCDATETIME(), 114) AS utc, @b AS batch,
           (SELECT size / 128 FROM sys.database_files WHERE type_desc = N'LOG') AS log_mb,
           (SELECT available_bytes / 1048576 FROM sys.dm_os_volume_stats(DB_ID(), 2)) AS free_mb_on_M,
           (SELECT log_reuse_wait_desc FROM sys.databases WHERE name = DB_NAME()) AS log_reuse_wait,
           (SELECT CONCAT(drs.synchronization_state_desc, ' ', drs.suspend_reason_desc)
            FROM sys.dm_hadr_database_replica_states AS drs
            JOIN sys.availability_replicas AS ar ON ar.replica_id = drs.replica_id
            WHERE drs.database_id = DB_ID() AND ar.replica_server_name = N'SQL02') AS copy_on_sql02;
END;
