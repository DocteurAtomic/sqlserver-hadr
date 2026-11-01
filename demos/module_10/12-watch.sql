-- ci: skip (Windows cluster of the course, not the containers)
-- Runs on the primary of Pacha, in sqlcmd, while the secondary is updated:
--     sqlcmd -S . -E -C -v SECONDS=900 -i 12-watch.sql
-- Module 10, clip 10.4: once a second, the health of the group and the state of the other
-- replica and of its copies, as the primary sees them. A line (UTC time) only when something
-- changes; the loop ends after SECONDS seconds, or 20 seconds after the group is back to
-- HEALTHY following a change.
SET NOCOUNT ON;
DECLARE @end datetime2 = DATEADD(second, $(SECONDS), SYSUTCDATETIME()), @now nvarchar(400),
        @last nvarchar(400) = N'', @changed bit = 0, @healthy_since datetime2;
WHILE SYSUTCDATETIME() < @end
BEGIN
    SELECT @now = CONCAT(N'group ', ags.synchronization_health_desc, N' | ',
        (SELECT STRING_AGG(CONCAT(ar.replica_server_name, N' ', rs.role_desc, N' ', rs.connected_state_desc,
                                  N' ', rs.synchronization_health_desc), N', ')
         FROM sys.availability_replicas AS ar
         JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
         WHERE rs.is_local = 0), N' | ',
        (SELECT STRING_AGG(CONCAT(DB_NAME(d.database_id), N' ', d.synchronization_state_desc), N', ')
                WITHIN GROUP (ORDER BY DB_NAME(d.database_id))
         FROM sys.dm_hadr_database_replica_states AS d WHERE d.is_local = 0))
    FROM sys.dm_hadr_availability_group_states AS ags
    JOIN sys.availability_groups AS g ON g.group_id = ags.group_id
    WHERE g.name = N'Pacha';
    IF @now <> @last
    BEGIN
        DECLARE @line nvarchar(500) = CONCAT(CONVERT(varchar(12), SYSUTCDATETIME(), 114), N' ', @now);
        RAISERROR(N'%s', 0, 1, @line) WITH NOWAIT;
        IF @last <> N'' SET @changed = 1;
        SET @last = @now;
        SET @healthy_since = IIF(@now LIKE N'group HEALTHY%', SYSUTCDATETIME(), NULL);
    END;
    IF @changed = 1 AND @healthy_since IS NOT NULL AND DATEDIFF(second, @healthy_since, SYSUTCDATETIME()) >= 20
        BREAK;
    WAITFOR DELAY '00:00:01';
END;
