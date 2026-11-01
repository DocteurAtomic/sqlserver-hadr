-- instance: pc1
-- Run by ag.sh. The database of the module, m13_registration, in full recovery with a full
-- backup, and the group AgPcs managed by an external cluster manager (Pacemaker): pc1 and pc2
-- synchronous, automatic seeding, failover mode EXTERNAL; pc3 configuration only.
SET NOCOUNT ON;
CREATE DATABASE m13_registration;
ALTER DATABASE m13_registration SET RECOVERY FULL;
GO
-- server: the instance that was primary when the row was committed.
CREATE TABLE m13_registration.dbo.Registration (
    id int IDENTITY PRIMARY KEY,
    email varchar(100) NOT NULL,
    created datetime2(3) NOT NULL DEFAULT SYSDATETIME(),
    server sysname NOT NULL DEFAULT @@SERVERNAME);
INSERT m13_registration.dbo.Registration (email) VALUES ('first@pachadata.example');
BACKUP DATABASE m13_registration TO DISK = N'/var/opt/mssql/data/m13_registration.bak' WITH INIT;
GO
CREATE AVAILABILITY GROUP AgPcs
WITH (CLUSTER_TYPE = EXTERNAL)
FOR DATABASE m13_registration
REPLICA ON
    N'pc1' WITH (ENDPOINT_URL = N'tcp://pc1:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
                 FAILOVER_MODE = EXTERNAL, SEEDING_MODE = AUTOMATIC),
    N'pc2' WITH (ENDPOINT_URL = N'tcp://pc2:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
                 FAILOVER_MODE = EXTERNAL, SEEDING_MODE = AUTOMATIC),
    N'pc3' WITH (ENDPOINT_URL = N'tcp://pc3:5022', AVAILABILITY_MODE = CONFIGURATION_ONLY);
