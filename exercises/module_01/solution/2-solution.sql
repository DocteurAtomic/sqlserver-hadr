-- instance: hadrlab1
-- Exercise of module 1, a solution. Other answers are right too: check.sh refuses only
-- what cannot work. Run after 1-start.sql.
USE ex_needs;
SET NOCOUNT ON;
GO
DELETE dbo.Choice;
INSERT dbo.Choice (database_name, solution, group_name, reason) VALUES
    (N'Registration', 'BASIC_AG_SYNC', N'agRegistration',
     N'RPO 0: only a synchronous copy loses nothing. Standard edition: a basic group, one database, '
   + N'two replicas; the 60 s RTO needs an automatic failover, so a Windows cluster under it. '
   + N'Billing cannot join this group: it gets its own.'),
    (N'Billing', 'LOG_SHIPPING',  NULL,
     N'RPO 15 min: a log backup every 5 min, copied and restored on the secondary, fits. '
   + N'A manual failover in 4 h is enough, and it runs in Standard edition.'),
    (N'Elearning', 'BACKUPS', NULL,
     N'RPO and RTO of a day, rebuilt every night: the nightly full backup, restored elsewhere, is enough.');
SELECT database_name, solution, group_name FROM dbo.Choice ORDER BY database_name;
GO
