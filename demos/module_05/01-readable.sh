#!/usr/bin/env bash
# Clip 5.1: open a secondary to the reports. The connections come from the sqlcmd of the
# container hadrlab1, inside the lab network (lands_on, setup/lib.sh). First the default
# (ALLOW_CONNECTIONS = NO): m05_reports on hadrlab3 refuses every connection, master accepts.
# Then hadrlab3 gets ALLOW_CONNECTIONS = READ_ONLY: refused without the read-only intent
# (-K ReadOnly, ApplicationIntent=ReadOnly), accepted with it; then ALL: accepted either way.
# An INSERT on the secondary fails (Msg 3906). hadrlab3 is left in READ_ONLY, which the next
# demos use. Run after 00-setup.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
setting() {  # ALLOW_CONNECTIONS of the secondary role of hadrlab3, read on the primary
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'hadrlab3, secondary role: ALLOW_CONNECTIONS = ', secondary_role_allow_connections_desc)
        FROM sys.availability_replicas WHERE replica_server_name = N'hadrlab3';"
}
matrix() {
    for opt in "-d m05_reports" "-d m05_reports -K ReadOnly" "-d master"; do
        printf '  %-34s -> %s\n' "hadrlab3 $opt" "$(lands_on hadrlab1 hadrlab3 $opt)"
    done
}
allow() {  # sets ALLOW_CONNECTIONS on hadrlab3, then waits, at most 30 seconds, until hadrlab3
           # itself reads the new value
    sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = $1));"
    for i in $(seq 1 30); do
        [ "$(sql hadrlab3 -h -1 -Q "SET NOCOUNT ON; SELECT secondary_role_allow_connections_desc FROM sys.availability_replicas WHERE replica_server_name = N'hadrlab3';" | tr -d '[:space:]')" = "$1" ] && return
        sleep 1
    done
    echo "hadrlab3 does not see ALLOW_CONNECTIONS = $1 after 30 seconds" >&2; exit 1
}
echo "== the default"
setting
matrix
echo
echo "== hadrlab1: ALLOW_CONNECTIONS = READ_ONLY on hadrlab3"
allow READ_ONLY
setting
matrix
echo
echo "== hadrlab1: ALLOW_CONNECTIONS = ALL on hadrlab3"
allow ALL
setting
matrix
echo
echo "== hadrlab3, connected with -K ReadOnly: a read, then an INSERT"
$engine exec -i hadrlab1 /opt/mssql-tools18/bin/sqlcmd -C -l 10 -S hadrlab3 -U sa -d m05_reports -K ReadOnly -W <<'SQL' 2>&1 || true
SET NOCOUNT ON;
SELECT COUNT(*) AS enrollments, MAX(enrolled_at) AS last_enrollment FROM dbo.Enrollment;
INSERT dbo.Enrollment (id, session_id, enrolled_at, email) VALUES (0, 1, SYSDATETIME(), 'report@pachadata.example');
SQL
echo
echo "== hadrlab1: back to READ_ONLY on hadrlab3"
allow READ_ONLY
setting
