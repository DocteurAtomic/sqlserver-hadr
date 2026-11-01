#!/usr/bin/env bash
# ci: skip (waits for the schedule of the Agent, twice, and leaves a failover half done in between)
# Clip 11.3: a failover of the contained group that resumes the user database only. The planned
# failover of module 6, by hand, hadrlab1 to hadrlab2: REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT
# = 1 and OFFLINE on hadrlab1, FORCE_FAILOVER_ALLOW_DATA_LOSS on hadrlab2, SET (ROLE = SECONDARY)
# on hadrlab1, then SET HADR RESUME on m11_signup alone, once suspended. The two databases of the
# group, m11_contained_master and m11_contained_msdb, stay suspended on hadrlab1: on hadrlab2,
# msdb of the group answers Msg 988, the job does not run at the next minute, and the Agent of
# hadrlab2 logs the same error every second. Then the two are resumed, the setting goes back to
# 0, and the job runs on hadrlab2 at the next minute. Leaves hadrlab2 primary of m11_contained:
# 09-contained-failover.sh fails back. Run after 07-contained.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
states() {
    for n in hadrlab1 hadrlab2; do
        sql $n -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'  ', @@SERVERNAME, N' ', rs.role_desc, N'  ', DB_NAME(d.database_id), N': ',
            d.synchronization_state_desc, IIF(d.is_suspended = 1, N', suspended (' + d.suspend_reason_desc + N')', N''))
            FROM sys.dm_hadr_database_replica_states AS d
            JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = d.replica_id
            JOIN sys.availability_groups AS g ON g.group_id = d.group_id
            WHERE g.name = N'm11_contained' AND d.is_local = 1 ORDER BY d.database_id;"
    done
}
next_minute() {  # waits until 15 seconds past the next minute, when the Agent has started the job
    local m; m=$(date -u +%M)
    timeout 90 bash -c "until [ \"\$(date -u +%M)\" != $m ] && [ \"\$(date -u +%S | sed 's/^0//')\" -ge 15 ]; do sleep 1; done"
    echo "  $(date -u +%T) UTC"
}
runs() { sql $1 -d m11_signup -Q "SET NOCOUNT ON; SELECT written_on, COUNT(*) AS runs, MAX(written_at) AS last_run FROM dbo.JobRun GROUP BY written_on ORDER BY written_on;"; }
echo "== the failover, hadrlab1 to hadrlab2, resuming m11_signup only"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP m11_contained SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1);
ALTER AVAILABILITY GROUP m11_contained OFFLINE;"
sql hadrlab2 -Q "ALTER AVAILABILITY GROUP m11_contained FORCE_FAILOVER_ALLOW_DATA_LOSS;"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP m11_contained SET (ROLE = SECONDARY);"
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
-- The new primary suspends the copy a moment after the role change: a RESUME sent earlier is lost.
DECLARE @t0 datetime2 = SYSDATETIME();
WHILE NOT EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states
                  WHERE is_local = 1 AND database_id = DB_ID(N'm11_signup') AND is_suspended = 1)
      AND DATEDIFF(second, @t0, SYSDATETIME()) < 60
    WAITFOR DELAY '00:00:00.500';
ALTER DATABASE m11_signup SET HADR RESUME;
SQL
sleep 5
echo "  $(date -u +%T) UTC"
states
echo
echo "== hadrlab2, in the context of the group: msdb"
sql hadrlab2 -d m11_contained_master -Q "SET NOCOUNT ON; SELECT COUNT(*) AS jobs FROM msdb.dbo.sysjobs;" 2>&1 | sed 's/^/  /' || true
echo
echo "== the next minute"
next_minute
runs hadrlab2
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; DECLARE @l TABLE (logdate datetime, process nvarchar(50), txt nvarchar(4000));
INSERT @l EXEC sys.xp_readerrorlog 0, 2, N'm11_contained_msdb';
SELECT CONCAT(N'  Agent log of hadrlab2, last minute: ', COUNT(*), N' lines such as: ', MAX(txt))
FROM @l WHERE logdate >= DATEADD(minute, -1, GETDATE());"
echo
echo "== hadrlab1: the two databases of the group resumed; hadrlab2: the setting back to 0"
sql hadrlab1 -Q "ALTER DATABASE m11_contained_master SET HADR RESUME; ALTER DATABASE m11_contained_msdb SET HADR RESUME;"
for i in $(seq 1 60); do
    late=$(sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.dm_hadr_database_replica_states AS d
        JOIN sys.availability_groups AS g ON g.group_id = d.group_id
        WHERE g.name = N'm11_contained' AND d.is_local = 0 AND d.synchronization_state_desc <> N'SYNCHRONIZED';" | tr -d '[:space:]')
    [ "$late" = 0 ] && break
    sleep 1
done
sql hadrlab2 -Q "ALTER AVAILABILITY GROUP m11_contained SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0);"
states
echo
echo "== the next minute"
next_minute
runs hadrlab2
