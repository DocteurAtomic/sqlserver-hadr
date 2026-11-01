-- Run by install.sh on hadrlab1. Creates master.dbo.reset_training, then restores
-- PachadataTraining if it is missing, puts it in the full recovery model and takes the
-- full backup that an availability group or log shipping needs to start from.
USE master;
GO
CREATE OR ALTER PROCEDURE dbo.reset_training
    @db sysname = N'PachadataTraining'  -- another name restores a separate copy
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @data nvarchar(260) = N'/var/opt/mssql/data/' + @db + N'.mdf',
            @log nvarchar(260) = N'/var/opt/mssql/data/' + @db + N'_log.ldf';
    DECLARE @q nvarchar(max), @n nvarchar(300) = QUOTENAME(@db);
    IF DB_ID(@db) IS NOT NULL
    BEGIN
        SET @q = N'ALTER DATABASE ' + @n + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
        EXEC (@q);
    END;
    RESTORE DATABASE @db
        FROM DISK = N'/var/opt/mssql/share/PachadataTraining-2026-10.bak'
        WITH REPLACE,
             MOVE N'PachadataTraining' TO @data,
             MOVE N'PachadataTraining_log' TO @log;
    -- The backup is at level 160 (built on SQL Server 2022); the course runs at level 170.
    -- It is delivered in the simple recovery model: availability groups and log shipping
    -- need the full model, and a first full backup to start the log chain.
    SET @q = N'ALTER DATABASE ' + @n + N' SET MULTI_USER; ALTER DATABASE ' + @n
           + N' SET COMPATIBILITY_LEVEL = 170; ALTER DATABASE ' + @n + N' SET RECOVERY FULL;';
    EXEC (@q);
    SET @q = N'BACKUP DATABASE ' + @n + N' TO DISK = N''/var/opt/mssql/share/' + @db
           + N'-full.bak'' WITH INIT, COMPRESSION;';
    EXEC (@q);
END;
GO
IF DB_ID(N'PachadataTraining') IS NULL
    EXEC dbo.reset_training;
ELSE
    PRINT 'PachadataTraining already exists: not restored.';
GO
SELECT name, compatibility_level, recovery_model_desc FROM sys.databases WHERE name = N'PachadataTraining';
