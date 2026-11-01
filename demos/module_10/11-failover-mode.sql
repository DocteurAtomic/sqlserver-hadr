-- ci: skip (Windows cluster of the course, not the containers)
-- Runs on the primary of Pacha, in sqlcmd, with the mode as a variable:
--     sqlcmd -S . -E -C -v MODE=MANUAL -i 11-failover-mode.sql      before the rolling update
--     sqlcmd -S . -E -C -v MODE=AUTOMATIC -i 11-failover-mode.sql   once both nodes are done
-- Module 10, clip 10.4: sets the failover mode of both replicas, then reads it back.
SET NOCOUNT ON;
ALTER AVAILABILITY GROUP Pacha MODIFY REPLICA ON N'SQL01' WITH (FAILOVER_MODE = $(MODE));
ALTER AVAILABILITY GROUP Pacha MODIFY REPLICA ON N'SQL02' WITH (FAILOVER_MODE = $(MODE));
SELECT replica_server_name AS replica, availability_mode_desc AS mode, failover_mode_desc AS failover
FROM sys.availability_replicas ORDER BY replica_server_name;
