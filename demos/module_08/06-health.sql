-- ci: skip (Windows cluster of the course, not the containers)
-- Runs on the primary replica, in sqlcmd. Module 8, clip 8.3: what decides an automatic
-- failover. The failover policy of the group (FAILURE_CONDITION_LEVEL, HEALTH_CHECK_TIMEOUT,
-- DB_FAILOVER), the session of the resource DLL that calls sp_server_diagnostics in a loop,
-- then one call of sp_server_diagnostics by hand: one row per component.
SET NOCOUNT ON;
SELECT name, failure_condition_level, health_check_timeout, db_failover,
       required_synchronized_secondaries_to_commit
FROM sys.availability_groups;
SELECT s.session_id, s.program_name, s.login_name, r.command, r.wait_type
FROM sys.dm_exec_sessions AS s
JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
WHERE r.wait_type = N'SP_SERVER_DIAGNOSTICS_SLEEP';
EXEC sp_server_diagnostics;
