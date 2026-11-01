-- ci: skip (Windows cluster of the course, not the containers)
-- Runs on SQL01, the primary of Pacha, in sqlcmd. Module 10, clip 10.4: creates m10_rolling,
-- where demos/module_08/02-client.ps1 -Database m10_rolling writes during the rolling update,
-- and adds it to Pacha; SQL02 seeds its copy itself (its replica is in automatic seeding, and
-- Pacha has had GRANT CREATE ANY DATABASE there since module 8). The database is small and
-- lives in the default folders of the instance; its full backup goes to NUL: it only opens the
-- log chain that the seeding needs.
SET NOCOUNT ON;
CREATE DATABASE m10_rolling;
ALTER DATABASE m10_rolling SET RECOVERY FULL;
GO
USE m10_rolling;
CREATE TABLE dbo.attempts (
    id int IDENTITY PRIMARY KEY,
    client_seq int NOT NULL,
    client_time datetime2(1) NOT NULL,
    server sysname NOT NULL DEFAULT @@SERVERNAME,
    written datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME());
GO
USE master;
BACKUP DATABASE m10_rolling TO DISK = 'NUL';
ALTER AVAILABILITY GROUP Pacha ADD DATABASE m10_rolling;
