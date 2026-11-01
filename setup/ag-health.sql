-- instance: the primary of the group (hadrlab1 in the demos of module 12)
-- The health of every availability database, read on the primary: one line per secondary copy,
-- with what the primary knows of it. Added by module 12. The two estimates follow Learn
-- ("Monitor performance for Always On availability groups"):
--   est_redo_s   redo_queue_size / redo_rate: the time the copy needs to finish its redo, the
--                part of a failover (RTO) that depends on the replica;
--   est_loss_s   0 when the copy is ready for a failover without loss (is_failover_ready, a
--                synchronous copy SYNCHRONIZED); otherwise the gap between the last commit
--                of the primary and the last commit redone on the copy, what SSMS shows as
--                the estimated data loss (RPO). The gap counts the redo still to do and the
--                time the primary wrote nothing: read it with send_q_kb, the log not sent.
-- Both are NULL, unknown, when the replica is not connected: the primary then knows neither
-- its queues nor how far it is. send_q_kb is NULL too for a suspended copy.
-- Usage: sql hadrlab1 < setup/ag-health.sql   (sql is in setup/lib.sh)
SET NOCOUNT ON;
SELECT g.name AS ag, ar.replica_server_name AS replica, DB_NAME(p.database_id) AS db,
       ISNULL(rs.connected_state_desc, N'?') AS connected,
       d.synchronization_state_desc AS sync, ISNULL(d.suspend_reason_desc, N'-') AS suspended,
       d.log_send_queue_size AS send_q_kb,
       d.redo_queue_size AS redo_q_kb, d.redo_rate AS redo_kb_s,
       CASE WHEN rs.connected_state_desc <> N'CONNECTED' OR d.redo_queue_size IS NULL THEN NULL
            WHEN d.redo_queue_size = 0 THEN 0
            WHEN d.redo_rate > 0 THEN CAST(1.0 * d.redo_queue_size / d.redo_rate AS decimal(9, 1))
       END AS est_redo_s,
       CASE WHEN rs.connected_state_desc <> N'CONNECTED' THEN NULL
            WHEN cs.is_failover_ready = 1 THEN 0
            ELSE CAST(DATEDIFF(millisecond, d.last_commit_time, p.last_commit_time) / 1000.0 AS decimal(9, 1))
       END AS est_loss_s
FROM sys.dm_hadr_database_replica_states AS p          -- the primary copy, on this instance
JOIN sys.availability_groups AS g ON g.group_id = p.group_id
JOIN sys.dm_hadr_database_replica_states AS d          -- each secondary copy, as the primary sees it
     ON d.group_id = p.group_id AND d.group_database_id = p.group_database_id AND d.is_primary_replica = 0
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
LEFT JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = d.replica_id
LEFT JOIN sys.dm_hadr_database_replica_cluster_states AS cs
     ON cs.replica_id = d.replica_id AND cs.group_database_id = d.group_database_id
WHERE p.is_local = 1 AND p.is_primary_replica = 1
ORDER BY g.name, db, replica;
