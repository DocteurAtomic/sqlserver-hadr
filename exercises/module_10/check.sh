#!/usr/bin/env bash
# Exercise of module 10, check. Reads the state of AgOps, never your commands, and exits with 0
# when: the group is on the three instances, hadrlab1 primary; the replica of hadrlab3 is not
# the one 1-start.sh created (its identifier, recorded in ex_operations.dbo.StartState, has
# changed: it was removed and added back); hadrlab3 has a single AgOps, connected; every copy
# of ex_operations, read on hadrlab1, is caught up (SYNCHRONIZED for hadrlab2, SYNCHRONIZING
# or SYNCHRONIZED for hadrlab3) and none is suspended. Otherwise exits with 1 and says what is
# missing.
# Usage: ./exercises/module_10/check.sh     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
missing=$(sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
DECLARE @m TABLE (line nvarchar(400));
DECLARE @g uniqueidentifier = (SELECT group_id FROM sys.availability_groups WHERE name = N'AgOps');
IF @g IS NULL
    INSERT @m VALUES (N'hadrlab1 has no group AgOps: run 1-start.sh again');
ELSE
BEGIN
    IF NOT EXISTS (SELECT * FROM sys.dm_hadr_availability_replica_states
                   WHERE group_id = @g AND is_local = 1 AND role_desc = N'PRIMARY')
        INSERT @m VALUES (N'hadrlab1 is not the primary of AgOps');
    INSERT @m SELECT CONCAT(n.name, N' is not a replica of AgOps')
    FROM (VALUES (N'hadrlab2'), (N'hadrlab3')) AS n (name)
    WHERE NOT EXISTS (SELECT * FROM sys.availability_replicas WHERE group_id = @g AND replica_server_name = n.name);
    IF EXISTS (SELECT * FROM sys.availability_replicas AS ar
               JOIN ex_operations.dbo.StartState AS s ON s.replica = ar.replica_server_name AND s.replica_id = ar.replica_id
               WHERE ar.group_id = @g)
        INSERT @m VALUES (N'the replica of hadrlab3 is still the one 1-start.sh created: remove it from AgOps, then add it back');
    INSERT @m SELECT CONCAT(ar.replica_server_name, N' is ', ISNULL(rs.connected_state_desc, N'not joined'), N' in AgOps')
    FROM sys.availability_replicas AS ar
    LEFT JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
    WHERE ar.group_id = @g AND ar.replica_server_name <> @@SERVERNAME
      AND ISNULL(rs.connected_state_desc, N'') <> N'CONNECTED';
    INSERT @m SELECT CONCAT(N'the copy of ex_operations on ', ar.replica_server_name, N' is ',
                            ISNULL(d.synchronization_state_desc, N'absent'),
                            IIF(d.is_suspended = 1, N', suspended (' + d.suspend_reason_desc + N')', N''))
    FROM sys.availability_replicas AS ar
    LEFT JOIN sys.dm_hadr_database_replica_states AS d
           ON d.replica_id = ar.replica_id AND d.database_id = DB_ID(N'ex_operations')
    WHERE ar.group_id = @g AND ar.replica_server_name <> @@SERVERNAME
      AND (d.is_suspended IS NULL OR d.is_suspended = 1
           OR NOT (d.synchronization_state_desc = N'SYNCHRONIZED'
                   OR (ar.availability_mode_desc = N'ASYNCHRONOUS_COMMIT' AND d.synchronization_state_desc = N'SYNCHRONIZING')));
END;
SELECT line FROM @m;
SQL
)
stale=$(sql hadrlab3 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.availability_groups AS g
JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.group_id = g.group_id AND rs.is_local = 1
WHERE g.name = N'AgOps' AND rs.connected_state_desc <> N'CONNECTED';" | tr -d '[:space:]')
[ "$stale" = 0 ] || missing="$missing
hadrlab3 still has a disconnected AgOps of its own: drop it there before the JOIN"
missing=$(printf '%s\n' "$missing" | grep -v '^ *$' || true)
if [ -n "$missing" ]; then
    echo "Not yet:"
    printf '%s\n' "$missing" | sed 's/^/  - /'
    exit 1
fi
echo "AgOps has its three replicas again, hadrlab3 added back, and no copy suspended or behind."
