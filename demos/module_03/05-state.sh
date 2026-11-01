#!/usr/bin/env bash
# Clip 3.3: the state of AgPacha, read on the primary, then on the asynchronous secondary,
# which only sees itself. Roles, connection and synchronization health of the replicas, the
# state of each copy of PachadataTraining with its last hardened LSN, the connections between
# endpoints with the login and the certificate of the peer and their encryption, and the
# seeding history.
# hadrlab3 is SYNCHRONIZING with the same LSN as the others: it is not late, the primary just
# does not wait for it. Appends that state to evidence/module_03.md. Run after 03-join.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
state=$(cat <<'SQL'
SET NOCOUNT ON;
SELECT @@SERVERNAME AS seen_from, g.name AS ag, gs.primary_replica,
       gs.synchronization_health_desc AS health
FROM sys.availability_groups AS g
LEFT JOIN sys.dm_hadr_availability_group_states AS gs ON gs.group_id = g.group_id;
SELECT ar.replica_server_name AS replica, ar.availability_mode_desc AS mode,
       rs.role_desc AS role, rs.connected_state_desc AS connected,
       rs.synchronization_health_desc AS health
FROM sys.availability_replicas AS ar
LEFT JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.replica_id = ar.replica_id
ORDER BY ar.replica_server_name;
SELECT ar.replica_server_name AS replica, DB_NAME(d.database_id) AS db,
       d.synchronization_state_desc AS sync, d.is_commit_participant AS commit_participant,
       d.log_send_queue_size AS send_queue_kb, d.redo_queue_size AS redo_queue_kb,
       d.last_hardened_lsn
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
ORDER BY ar.replica_server_name, db;
SQL
)
for n in hadrlab1 hadrlab3; do
    echo "== $n"
    sql $n -Q "$state"
done
echo
echo "== hadrlab1, the connections between endpoints:"
sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT ISNULL(c.address, N'-') AS peer, IIF(c.is_accept = 1, N'in', N'out') AS direction, c.state_desc AS state,
       c.principal_name AS login, cert.name AS peer_certificate,
       c.encryption_algorithm_desc AS encryption
FROM sys.dm_db_mirroring_connections AS c
LEFT JOIN master.sys.certificates AS cert ON cert.certificate_id = c.peer_certificate_id
ORDER BY c.address, c.is_accept;"
echo
echo "== hadrlab1, the seeding history (sys.dm_hadr_automatic_seeding):"
sql hadrlab1 -Q "SET NOCOUNT ON;
SELECT ar.replica_server_name AS replica, adc.database_name AS db, s.current_state,
       s.number_of_attempts AS attempts,
       FORMAT(DATEDIFF(millisecond, s.start_time, s.completion_time) / 1000.0, N'0.0') AS seconds
FROM sys.dm_hadr_automatic_seeding AS s
JOIN sys.availability_replicas AS ar ON ar.replica_id = s.ag_remote_replica_id
JOIN sys.availability_databases_cluster AS adc ON adc.group_database_id = s.ag_db_id
ORDER BY s.start_time;"
line=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
SELECT STRING_AGG(CONCAT(ar.replica_server_name, N' ', ar.availability_mode_desc, N' ',
           d.synchronization_state_desc, N' (commit participant ', d.is_commit_participant,
           N', LSN ', IIF(d.last_hardened_lsn = p.last_hardened_lsn, N'equal to', N'behind'), N' the primary)'), N'; ')
FROM sys.dm_hadr_database_replica_states AS d
JOIN sys.availability_replicas AS ar ON ar.replica_id = d.replica_id
CROSS JOIN (SELECT last_hardened_lsn FROM sys.dm_hadr_database_replica_states
            WHERE is_local = 1 AND database_id = DB_ID(N'PachadataTraining')) AS p
WHERE d.is_local = 0 AND d.database_id = DB_ID(N'PachadataTraining');")
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 3, availability group AgPacha without a cluster, PachadataTraining at rest (three containers on one host): $line" >> evidence/module_03.md
