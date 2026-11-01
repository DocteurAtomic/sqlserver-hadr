-- instance: hadrlab1
-- Clip 1.2: the edition decides which solutions an instance offers. Reads the edition of
-- the lab, then tries a basic availability group, the one of Standard edition: the lab
-- refuses it (error 534), and nothing is created. Run after 00-setup.sh.
USE master;
SET NOCOUNT ON;
GO
-- 1. The edition: Developer has every feature of Enterprise (EngineEdition 3).
SELECT SERVERPROPERTY('Edition') AS edition,
       SERVERPROPERTY('EngineEdition') AS engine_edition,
       SERVERPROPERTY('IsHadrEnabled') AS is_hadr_enabled,
       SERVERPROPERTY('IsClustered') AS is_clustered;
GO
-- 2. A basic availability group for m01_registration. The edition is checked when the
--    statement compiles (error 534, level 15): it runs through EXEC, so that CATCH sees it.
BEGIN TRY
    EXEC (N'CREATE AVAILABILITY GROUP m01_basic
    WITH (BASIC, CLUSTER_TYPE = NONE)
    FOR DATABASE m01_registration
    REPLICA ON
        N''hadrlab1'' WITH (ENDPOINT_URL = N''tcp://hadrlab1:5022'',
                          AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL),
        N''hadrlab2'' WITH (ENDPOINT_URL = N''tcp://hadrlab2:5022'',
                          AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL);');
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
GO
-- 3. Nothing was created.
SELECT COUNT(*) AS availability_groups FROM sys.availability_groups;
-- 4. The endpoint that availability groups use is still a database mirroring endpoint.
SELECT name, type_desc, role_desc, state_desc FROM sys.database_mirroring_endpoints;
GO
