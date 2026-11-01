-- instance: hadrlab1
-- Clip 3.3: changing a replica, on the primary. FAILOVER_MODE = AUTOMATIC is refused without
-- a cluster (Msg 47101). hadrlab3 then goes from asynchronous to synchronous commit: it
-- becomes SYNCHRONIZED and a commit participant, after a wait of at most 60 seconds, timed;
-- then it goes back to asynchronous commit, the state that the next modules expect.
-- Run after 03-join.sh.
USE master;
SET NOCOUNT ON;
GO
BEGIN TRY
    ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (FAILOVER_MODE = AUTOMATIC);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
GO
CREATE OR ALTER PROCEDURE #replica @step varchar(30)
AS
    SELECT @step AS step, ar.replica_server_name AS replica, ar.availability_mode_desc AS mode,
           d.synchronization_state_desc AS sync, d.is_commit_participant AS commit_participant
    FROM sys.availability_replicas AS ar
    JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id
    WHERE ar.replica_server_name = N'hadrlab3' AND d.database_id = DB_ID(N'PachadataTraining');
GO
EXEC #replica 'before';
DECLARE @t0 datetime2(3) = SYSDATETIME();
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT);
EXEC #replica 'right after';
WHILE NOT EXISTS (SELECT * FROM sys.availability_replicas AS ar
                  JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id
                  WHERE ar.replica_server_name = N'hadrlab3' AND d.synchronization_state_desc = N'SYNCHRONIZED')
      AND DATEDIFF(second, @t0, SYSDATETIME()) < 60
    WAITFOR DELAY '00:00:00.200';
IF NOT EXISTS (SELECT * FROM sys.availability_replicas AS ar
               JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id
               WHERE ar.replica_server_name = N'hadrlab3' AND d.synchronization_state_desc = N'SYNCHRONIZED')
    THROW 50000, N'hadrlab3 is not SYNCHRONIZED 60 seconds after the change', 1;
SELECT FORMAT(DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0, N'0.0') AS seconds_to_synchronized;
EXEC #replica 'synchronous';
ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT);
WAITFOR DELAY '00:00:01';
EXEC #replica 'back to asynchronous';
GO
