-- instance: hadrlab1
-- Exercise of module 1, starting state. Creates the database ex_needs on hadrlab1: the
-- needs of three databases of PachaData (dbo.Need), the edition PachaData pays for
-- (dbo.Licence), the solutions to choose from (dbo.Solution), and the empty table of your
-- choices (dbo.Choice). Run it again to start over: it drops ex_needs first.
USE master;
SET NOCOUNT ON;
GO
IF DB_ID(N'ex_needs') IS NOT NULL
BEGIN
    ALTER DATABASE ex_needs SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ex_needs;
END;
GO
CREATE DATABASE ex_needs;
GO
USE ex_needs;
GO
CREATE TABLE dbo.Licence (edition varchar(20) NOT NULL);
INSERT dbo.Licence VALUES ('Standard');

CREATE TABLE dbo.Need (
    database_name sysname NOT NULL PRIMARY KEY,
    purpose nvarchar(200) NOT NULL,
    rpo_seconds int NOT NULL,      -- data the business accepts to lose, in seconds
    rto_seconds int NOT NULL,      -- time the business accepts to be stopped, in seconds
    remark nvarchar(300) NULL);
INSERT dbo.Need VALUES
    (N'Registration', N'The registration site: sessions, places left, new registrations', 0, 60,
     N'The site reads Billing in the same requests: the team would like both databases to fail over together.'),
    (N'Billing', N'Invoices and payments', 900, 14400, NULL),
    (N'Elearning', N'The e-learning platform: progress of the trainees, reports', 86400, 86400,
     N'Rebuilt every night from the platform logs.');

CREATE TABLE dbo.Solution (
    code varchar(20) NOT NULL PRIMARY KEY,
    description nvarchar(200) NOT NULL);
INSERT dbo.Solution VALUES
    ('BACKUPS',        N'Full, differential and log backups, restored on another server'),
    ('LOG_SHIPPING',   N'Log shipping to a secondary server'),
    ('FCI',            N'Failover cluster instance (Windows cluster and shared storage)'),
    ('BASIC_AG_SYNC',  N'Basic availability group, synchronous commit'),
    ('BASIC_AG_ASYNC', N'Basic availability group, asynchronous commit'),
    ('AG_SYNC',        N'Availability group, synchronous commit'),
    ('AG_ASYNC',       N'Availability group, asynchronous commit'),
    ('DISTRIBUTED_AG', N'Distributed availability group between two sites');

CREATE TABLE dbo.Choice (
    database_name sysname NOT NULL PRIMARY KEY REFERENCES dbo.Need (database_name),
    solution varchar(20) NOT NULL REFERENCES dbo.Solution (code),
    group_name sysname NULL,       -- for an availability group: the group of the database
    reason nvarchar(400) NOT NULL);
GO
SELECT database_name, rpo_seconds, rto_seconds, remark FROM dbo.Need ORDER BY rpo_seconds;
GO
