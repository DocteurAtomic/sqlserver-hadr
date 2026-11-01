#!/usr/bin/env bash
# Planned failover of an availability group without a cluster (CLUSTER_TYPE = NONE), where
# ALTER AVAILABILITY GROUP ... FAILOVER is refused (Msg 47122). The sequence of module 6, for
# any number of replicas:
#   1. the target must be a synchronous secondary, SYNCHRONIZED for every database, its last
#      hardened LSN equal to the primary's (checked, never assumed: the script stops otherwise);
#   2. on the primary, REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1, then OFFLINE: from
#      then on nothing commits there (the statements in flight fail with Msg 983);
#   3. on the target, FORCE_FAILOVER_ALLOW_DATA_LOSS, which loses nothing here since the
#      target has everything the primary committed;
#   4. on the old primary and on every other secondary, SET (ROLE = SECONDARY): a secondary
#      that does not get it keeps calling the old primary and never synchronizes again;
#   5. on each secondary, every database the new primary suspends ("failover from partner")
#      is resumed once it shows as suspended, read on the primary every second, at most two
#      minutes (a RESUME sent before the suspension arrives is lost);
#   6. on the new primary, REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT back to the value it
#      had before step 2.
# A listener is not moved: it stays on the address of the old primary (module 5); drop it and
# create it again on the address of the new primary. Prints one line per step, and the time
# from step 2 to the end of step 6. Added by module 6.
# Usage: ./setup/ag-failover.sh AgPacha hadrlab2     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/.."
. setup/lib.sh
ag=${1:?usage: setup/ag-failover.sh <availability group> <target replica>}
target=${2:?usage: setup/ag-failover.sh <availability group> <target replica>}
role_of() {  # the role of the local replica of the group on an instance
    sql "$1" -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL((SELECT rs.role_desc FROM sys.availability_groups AS g
        JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.group_id = g.group_id AND rs.is_local = 1
        WHERE g.name = N'$ag'), N'NONE');" | tr -d '[:space:]'
}
primary=""
others=""
for n in $nodes; do
    case $(role_of $n) in
        PRIMARY) primary="$primary $n" ;;
        NONE) ;;
        *) [ $n = "$target" ] || others="$others $n" ;;
    esac
done
primary=${primary# }
if [ -z "$primary" ] || [ "$primary" != "${primary% *}" ]; then
    echo "ag-failover: $ag needs exactly one primary, found: '${primary:-none}'" >&2; exit 1
fi
if [ "$primary" = "$target" ]; then echo "ag-failover: $target is already the primary of $ag" >&2; exit 1; fi
t0=$(date +%s.%N)
elapsed() { awk -v s=$t0 -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }'; }
# 1 and 2, in one batch on the primary.
required=$(sql $primary -h -1 -v AG="$ag" TARGET="$target" <<'SQL' | tr -d '[:space:]'
SET NOCOUNT ON;
DECLARE @ag sysname = N'$(AG)', @target sysname = N'$(TARGET)', @bad nvarchar(400), @q nvarchar(max);
SELECT @bad = STRING_AGG(CONCAT(DB_NAME(d.database_id), N' ', d.synchronization_state_desc,
                                IIF(d.last_hardened_lsn = p.last_hardened_lsn, N'', N', LSN behind')), N'; ')
FROM sys.availability_groups AS g
JOIN sys.availability_replicas AS ar ON ar.group_id = g.group_id AND ar.replica_server_name = @target
JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id
JOIN sys.dm_hadr_database_replica_states AS p ON p.group_database_id = d.group_database_id AND p.is_local = 1
WHERE g.name = @ag AND (ar.availability_mode_desc <> N'SYNCHRONOUS_COMMIT'
                        OR d.synchronization_state_desc <> N'SYNCHRONIZED' OR d.last_hardened_lsn <> p.last_hardened_lsn);
IF @bad IS NOT NULL OR NOT EXISTS (SELECT * FROM sys.availability_replicas AS ar JOIN sys.availability_groups AS g
                                   ON g.group_id = ar.group_id WHERE g.name = @ag AND ar.replica_server_name = @target)
BEGIN
    RAISERROR(N'ag-failover: %s is not a synchronous secondary caught up for every database (%s): nothing done', 16, 1,
              @target, @bad);
    RETURN;
END;
SELECT required_synchronized_secondaries_to_commit FROM sys.availability_groups WHERE name = @ag;
SET @q = N'ALTER AVAILABILITY GROUP ' + QUOTENAME(@ag) + N' SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1);'
       + N'ALTER AVAILABILITY GROUP ' + QUOTENAME(@ag) + N' OFFLINE;';
EXEC (@q);
SQL
)
echo "$primary: $target checked, required synchronized secondaries 1, $ag OFFLINE (+$(elapsed) s)"
sql $target -Q "ALTER AVAILABILITY GROUP [$ag] FORCE_FAILOVER_ALLOW_DATA_LOSS;"
echo "$target: FORCE_FAILOVER_ALLOW_DATA_LOSS (+$(elapsed) s)"
for n in $primary $others; do
    sql $n -Q "ALTER AVAILABILITY GROUP [$ag] SET (ROLE = SECONDARY);"
    echo "$n: SET (ROLE = SECONDARY) (+$(elapsed) s)"
done
# 5. Read on the new primary which copies are not caught up; resume those that are suspended.
for i in $(seq 1 120); do
    late=$(sql $target -h -1 -s '|' -v AG="$ag" <<'SQL' | tr -d '\r' | grep -v '^ *$' || true
SET NOCOUNT ON;
SELECT CONCAT(ar.replica_server_name, N'|', DB_NAME(d.database_id))
FROM sys.availability_groups AS g
JOIN sys.availability_replicas AS ar ON ar.group_id = g.group_id
JOIN sys.dm_hadr_database_replica_states AS d ON d.replica_id = ar.replica_id
WHERE g.name = N'$(AG)' AND d.is_local = 0
  AND NOT (d.synchronization_state_desc = N'SYNCHRONIZED'
           OR (ar.availability_mode_desc = N'ASYNCHRONOUS_COMMIT' AND d.synchronization_state_desc = N'SYNCHRONIZING'));
SQL
)
    [ -z "$late" ] && break
    for l in $late; do
        n=${l%%|*} db=${l#*|}
        s=$(sql $n -h -1 -Q "SET NOCOUNT ON; SELECT is_suspended FROM sys.dm_hadr_database_replica_states
            WHERE is_local = 1 AND database_id = DB_ID(N'$db');" | tr -d '[:space:]')
        if [ "$s" = 1 ]; then
            sql $n -Q "ALTER DATABASE [$db] SET HADR RESUME;"
            echo "$n: $db suspended by the failover, SET HADR RESUME (+$(elapsed) s)"
        fi
    done
    # An asynchronous copy reports SYNCHRONIZING once the primary writes log: a checkpoint does.
    # While the setting is 1 and no secondary is synchronized yet, the database refuses it
    # (Msg 988): that is expected, the next turn tries again.
    sql $target -h -1 -Q "SET NOCOUNT ON; DECLARE @q nvarchar(max) = N'';
        SELECT @q += N'BEGIN TRY USE ' + QUOTENAME(DB_NAME(database_id)) + N'; CHECKPOINT; END TRY BEGIN CATCH END CATCH; '
        FROM sys.dm_hadr_database_replica_states WHERE is_local = 1; EXEC (@q);" >/dev/null 2>&1 || true
    sleep 1
done
if [ -n "$late" ]; then
    echo "ag-failover: not caught up two minutes after the failover: $late" >&2; exit 1
fi
sql $target -Q "ALTER AVAILABILITY GROUP [$ag] SET (REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = ${required:-0});"
echo "$target: every secondary caught up, required synchronized secondaries back to ${required:-0}"
echo "$ag failed over from $primary to $target in $(elapsed) s"
