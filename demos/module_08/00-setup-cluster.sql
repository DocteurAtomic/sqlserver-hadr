-- ci: skip (Windows cluster of the course, not the containers)
-- Runs on SQL01, the primary of Pacha, in sqlcmd, once 00-setup-cluster.ps1 has made M: on
-- both nodes. Creates m08_registrations on M:, where 02-client.ps1 and 09-writer.ps1 write,
-- and adds it to Pacha. SQL02 seeds its copy itself (SEEDING_MODE = AUTOMATIC on its replica):
-- run first, on SQL02, ALTER AVAILABILITY GROUP Pacha GRANT CREATE ANY DATABASE;
SET NOCOUNT ON;
CREATE DATABASE m08_registrations
ON (NAME = m08_registrations, FILENAME = 'M:\data\m08_registrations.mdf', SIZE = 16MB, FILEGROWTH = 16MB)
LOG ON (NAME = m08_registrations_log, FILENAME = 'M:\data\m08_registrations_log.ldf', SIZE = 16MB, FILEGROWTH = 16MB);
ALTER DATABASE m08_registrations SET RECOVERY FULL;
GO
USE m08_registrations;
CREATE TABLE dbo.attempts (
    id int IDENTITY PRIMARY KEY,
    client_seq int NOT NULL,
    client_time datetime2(1) NOT NULL,
    server sysname NOT NULL DEFAULT @@SERVERNAME,
    written datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME());
GO
USE master;
BACKUP DATABASE m08_registrations TO DISK = 'C:\m08\m08_registrations.bak' WITH INIT, FORMAT;
ALTER AVAILABILITY GROUP Pacha ADD DATABASE m08_registrations;
