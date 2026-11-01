#!/usr/bin/env bash
# Exercise of module 11: checks that the login ex_app and the job ex_heartbeat work on whichever
# replica of AgObjects is the primary, and that the job acts there only. It reads the state, never
# the commands:
#   - AgObjects has one primary, hadrlab1 or hadrlab2, and the other replica is its secondary;
#   - the login ex_app exists on both instances with the same SID, the SID of the user ex_app of
#     ex_objects (read on the primary);
#   - ex_app, with its password Ex-App-2026!, connects to the primary in ex_objects, and writes a
#     row there;
#   - the job ex_heartbeat exists on both instances; started on each of them (in sa: ex_app has no
#     access to msdb, Msg 229), it succeeds on both, and only the run on the primary adds a row to
#     dbo.Heartbeat.
# The check starts the job and writes, so it adds two rows each time it runs. Exits with 0 when
# everything holds, with 1 otherwise, saying what is missing.
# Usage: ./exercises/module_11/check.sh     (with Podman: ENGINE=podman ...)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
fail=0
ok() { echo "ok   $*"; }
ko() { echo "FAIL $*"; fail=1; }
role_of() {
    sql $1 -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL((SELECT rs.role_desc FROM sys.availability_groups AS g
        JOIN sys.dm_hadr_availability_replica_states AS rs ON rs.group_id = g.group_id AND rs.is_local = 1
        WHERE g.name = N'AgObjects'), N'no AgObjects');" 2>/dev/null | tr -d '\r' | xargs
}
r1=$(role_of hadrlab1); r2=$(role_of hadrlab2)
if [ "$r1" = PRIMARY ] && [ "$r2" = SECONDARY ]; then primary=hadrlab1; secondary=hadrlab2
elif [ "$r2" = PRIMARY ] && [ "$r1" = SECONDARY ]; then primary=hadrlab2; secondary=hadrlab1
else
    echo "FAIL AgObjects: hadrlab1 is '${r1:-no answer}', hadrlab2 is '${r2:-no answer}'; one PRIMARY and one SECONDARY expected (run exercises/module_11/1-start.sh to start over)"
    exit 1
fi
ok "AgObjects: $primary primary, $secondary secondary"
# The SIDs.
sid_of() {
    sql $1 -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL((SELECT CONVERT(varchar(100), sid, 1) FROM sys.server_principals
        WHERE name = N'ex_app' AND type = 'S'), N'none');" 2>/dev/null | tr -d '[:space:]'
}
s1=$(sid_of $primary); s2=$(sid_of $secondary)
su=$(sql $primary -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL((SELECT CONVERT(varchar(100), sid, 1)
    FROM ex_objects.sys.database_principals WHERE name = N'ex_app'), N'none');" 2>/dev/null | tr -d '[:space:]')
for p in "$primary $s1" "$secondary $s2"; do
    set -- $p
    if [ "$2" = none ] || [ -z "$2" ]; then ko "$1: no SQL login ex_app"
    elif [ "$2" = "$su" ]; then ok "$1: the login ex_app has the SID of the user ex_app of ex_objects ($su)"
    else ko "$1: the login ex_app has the SID $2, the user ex_app of ex_objects has $su: an orphan user there after a failover"; fi
done
# The application, on the primary.
out=$($engine exec -i -e SQLCMDPASSWORD='Ex-App-2026!' $primary /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U ex_app -C -b -h -1 -W \
    -d ex_objects -Q "SET NOCOUNT ON; INSERT dbo.Heartbeat (written_on) VALUES (N'ex_app'); SELECT CONCAT(SUSER_SNAME(), N'@', @@SERVERNAME);" 2>&1 \
    | tr -d '\r' | grep -v '^ *$')
if [ "$out" = "ex_app@$primary" ]; then ok "$primary: ex_app connects to ex_objects with its password, and writes"
else ko "$primary: ex_app cannot work in ex_objects: $(echo "$out" | sed 's/^Sqlcmd: Error: Microsoft ODBC Driver 18 for SQL Server : //' | head -2 | xargs)"; fi
# The job, on both replicas.
count() {
    sql $primary -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM ex_objects.dbo.Heartbeat WHERE written_on = N'$1';" 2>/dev/null | tr -d '[:space:]'
}
for n in $secondary $primary; do
    has=$(sql $n -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name = N'ex_heartbeat';" 2>/dev/null | tr -d '[:space:]')
    if [ "$has" != 1 ]; then ko "$n: no job ex_heartbeat"; continue; fi
    before=$(count $n)
    if res=$(run_job $n ex_heartbeat 60 2>&1); then
        after=$(count $n)
        if [ $n = $primary ]; then
            if [ "$after" -gt "$before" ]; then ok "$n: ex_heartbeat succeeds and writes a row (the primary)"
            else ko "$n: ex_heartbeat succeeds on the primary but writes nothing into dbo.Heartbeat"; fi
        else
            if [ "$after" = "$before" ]; then ok "$n: ex_heartbeat succeeds and writes nothing (the secondary)"
            else ko "$n: ex_heartbeat wrote a row from the secondary"; fi
        fi
    else
        msg=$(sql $n -h -1 -Q "SET NOCOUNT ON; SELECT TOP (1) CONCAT(N'step ', h.step_id, N': ', LEFT(h.message, 160))
            FROM msdb.dbo.sysjobhistory AS h JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
            WHERE j.name = N'ex_heartbeat' AND h.step_id > 0 AND h.run_status <> 1 ORDER BY h.instance_id DESC;" 2>/dev/null | xargs)
        ko "$n: ex_heartbeat fails ($msg)"
    fi
done
if [ $fail = 1 ]; then echo "The login and the job do not follow AgObjects yet."; exit 1; fi
echo "ex_app and ex_heartbeat follow AgObjects: the application works on $primary, and the job acts on the primary only."
