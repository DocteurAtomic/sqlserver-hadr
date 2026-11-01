-- Run by the cleanup scripts, with the variable DB set to a LIKE pattern ("m02[_]%"). Removes
-- the log shipping configuration of the matching databases on this instance, as a primary
-- (its secondaries first) and as a secondary, with their jobs and the rows of their monitor,
-- then the alert job when no log shipping is left on the instance. It drops no database.
SET NOCOUNT ON;
DECLARE @db sysname, @srv sysname, @sdb sysname;
DECLARE p CURSOR LOCAL FAST_FORWARD FOR
    SELECT pd.primary_database, ps.secondary_server, ps.secondary_database
    FROM msdb.dbo.log_shipping_primary_databases AS pd
    JOIN msdb.dbo.log_shipping_primary_secondaries AS ps ON ps.primary_id = pd.primary_id
    WHERE pd.primary_database LIKE N'$(DB)';
OPEN p;
FETCH p INTO @db, @srv, @sdb;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC master.dbo.sp_delete_log_shipping_primary_secondary
        @primary_database = @db, @secondary_server = @srv, @secondary_database = @sdb;
    FETCH p INTO @db, @srv, @sdb;
END;
CLOSE p;
DEALLOCATE p;
DECLARE d CURSOR LOCAL FAST_FORWARD FOR
    SELECT primary_database FROM msdb.dbo.log_shipping_primary_databases
    WHERE primary_database LIKE N'$(DB)';
OPEN d;
FETCH d INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC master.dbo.sp_delete_log_shipping_primary_database @database = @db;
    PRINT N'log shipping primary ' + @db + N' removed on ' + @@SERVERNAME;
    FETCH d INTO @db;
END;
CLOSE d;
DEALLOCATE d;
DECLARE s CURSOR LOCAL FAST_FORWARD FOR
    SELECT secondary_database FROM msdb.dbo.log_shipping_secondary_databases
    WHERE secondary_database LIKE N'$(DB)';
OPEN s;
FETCH s INTO @db;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC master.dbo.sp_delete_log_shipping_secondary_database @secondary_database = @db;
    PRINT N'log shipping secondary ' + @db + N' removed on ' + @@SERVERNAME;
    FETCH s INTO @db;
END;
CLOSE s;
DEALLOCATE s;
IF NOT EXISTS (SELECT * FROM msdb.dbo.log_shipping_primary_databases)
   AND NOT EXISTS (SELECT * FROM msdb.dbo.log_shipping_secondary_databases)
   AND EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name LIKE N'LSAlert[_]%')
BEGIN
    EXEC master.dbo.sp_delete_log_shipping_alert_job;
    PRINT N'log shipping alert job removed on ' + @@SERVERNAME;
END;
