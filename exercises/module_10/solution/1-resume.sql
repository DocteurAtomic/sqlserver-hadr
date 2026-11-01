-- instance: hadrlab2
-- Exercise of module 10, solution, step 1: the copy of hadrlab2 was suspended (on hadrlab1,
-- sys.dm_hadr_database_replica_states says is_suspended 1, SUSPEND_FROM_USER). A suspension
-- run on a secondary is resumed on that secondary.
ALTER DATABASE ex_operations SET HADR RESUME;
