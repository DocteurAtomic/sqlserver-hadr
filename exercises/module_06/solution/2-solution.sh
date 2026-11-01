#!/usr/bin/env bash
# Exercise of module 6, a solution. Run after 1-start.sh. The planned failover of AgBascule from
# hadrlab1 to hadrlab2, statement by statement, each one where it acts: the check that
# hadrlab2 is SYNCHRONIZED; on hadrlab1, REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1 and
# OFFLINE; on hadrlab2, FORCE_FAILOVER_ALLOW_DATA_LOSS; on hadrlab1, SET (ROLE = SECONDARY),
# then RESUME once its copy shows as suspended (at most a minute); on hadrlab2, the setting back
# to 0 and a row written. There is no third replica here: with three, each other secondary
# needs its own SET (ROLE = SECONDARY) and RESUME (setup/ag-failover.sh does it for any number).
# Appends the duration to evidence/module_06.md. Other solutions hold too: check.sh reads the
# state.
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
t0=$(date +%s.%N)
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
IF NOT EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states AS d
               JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
               WHERE ar.replica_server_name = N'hadrlab2' AND d.database_id = DB_ID(N'ex_bascule')
                 AND d.synchronization_state_desc = N'SYNCHRONIZED')
    THROW 50000, N'hadrlab2 is not SYNCHRONIZED: no planned failover', 1;
ALTER AVAILABILITY GROUP AgBascule SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1);
ALTER AVAILABILITY GROUP AgBascule OFFLINE;
SQL
sql hadrlab2 -Q "ALTER AVAILABILITY GROUP AgBascule FORCE_FAILOVER_ALLOW_DATA_LOSS;"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgBascule SET (ROLE = SECONDARY);"
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
-- The new primary suspends the copy a moment after the role change: a RESUME sent earlier is lost.
DECLARE @t0 datetime2 = SYSDATETIME();
WHILE NOT EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states
                  WHERE is_local = 1 AND database_id = DB_ID(N'ex_bascule') AND is_suspended = 1)
      AND DATEDIFF(second, @t0, SYSDATETIME()) < 60
    WAITFOR DELAY '00:00:00.500';
IF NOT EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states
               WHERE is_local = 1 AND database_id = DB_ID(N'ex_bascule') AND is_suspended = 1)
    THROW 50000, N'the copy of hadrlab1 is not suspended a minute after SET (ROLE = SECONDARY)', 1;
ALTER DATABASE ex_bascule SET HADR RESUME;
SQL
sql hadrlab2 -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @t0 datetime2 = SYSDATETIME();
WHILE NOT EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states AS d
                  JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
                  WHERE ar.replica_server_name = N'hadrlab1' AND d.database_id = DB_ID(N'ex_bascule')
                    AND d.synchronization_state_desc = N'SYNCHRONIZED')
      AND DATEDIFF(second, @t0, SYSDATETIME()) < 60
BEGIN
    -- The checkpoint writes log, which moves the copy forward; while hadrlab1 is not synchronized
    -- and the setting is 1, the database refuses it (Msg 988), and the loop reads again.
    BEGIN TRY EXEC (N'USE ex_bascule; CHECKPOINT;'); END TRY BEGIN CATCH END CATCH;
    WAITFOR DELAY '00:00:00.500';
END;
IF NOT EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states AS d
               JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
               WHERE ar.replica_server_name = N'hadrlab1' AND d.database_id = DB_ID(N'ex_bascule')
                 AND d.synchronization_state_desc = N'SYNCHRONIZED')
    THROW 50000, N'hadrlab1 is not SYNCHRONIZED a minute after RESUME', 1;
ALTER AVAILABILITY GROUP AgBascule SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0);
INSERT ex_bascule.dbo.Registration (batch, email) VALUES ('after failover', 'after@pachadata.example');
SELECT batch, written_on, COUNT(*) AS rows_on_hadrlab2 FROM ex_bascule.dbo.Registration GROUP BY batch, written_on;
SQL
took=$(awk -v s=$t0 -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }')
echo "AgBascule failed over from hadrlab1 to hadrlab2 in $took s"
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 6, exercise, planned failover of AgBascule (two replicas) from hadrlab1 to hadrlab2: $took s, the 500 rows written before it all on the new primary; three containers on one host" >> evidence/module_06.md
