-- instance: hadrlab1
-- Clip 3.2: the availability group AgPacha, without a cluster, created on hadrlab1, its
-- primary, for PachadataTraining (full recovery model, full backup taken by install.sh).
-- Three replicas: hadrlab1 and hadrlab2 in synchronous commit, hadrlab3 in asynchronous
-- commit, manual failover (the only mode CLUSTER_TYPE = NONE accepts), automatic seeding.
-- The secondaries join in 03-join.sh. Run after 00-setup.sh.
USE master;
SET NOCOUNT ON;
GO
CREATE AVAILABILITY GROUP AgPacha
WITH (CLUSTER_TYPE = NONE)
FOR DATABASE PachadataTraining
REPLICA ON
    N'hadrlab1' WITH (ENDPOINT_URL = N'tcp://hadrlab1:5022',
                      AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL,
                      SEEDING_MODE = AUTOMATIC),
    N'hadrlab2' WITH (ENDPOINT_URL = N'tcp://hadrlab2:5022',
                      AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL,
                      SEEDING_MODE = AUTOMATIC),
    N'hadrlab3' WITH (ENDPOINT_URL = N'tcp://hadrlab3:5022',
                      AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL,
                      SEEDING_MODE = AUTOMATIC);
GO
-- What the primary knows right after the creation: the two secondaries have not joined yet.
SELECT ar.replica_server_name AS replica, ar.availability_mode_desc AS mode,
       rs.role_desc AS role, rs.connected_state_desc AS connected
FROM sys.availability_replicas AS ar
LEFT JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
ORDER BY ar.replica_server_name;
GO
