#!/usr/bin/env bash
# Clip 11.1: the repair that moves the problem. On hadrlab2, the primary, ALTER USER ... WITH
# LOGIN maps the user to the login of hadrlab2: the application connects again. But the user
# lives in the database, and the change goes to the secondaries with the log: the user now holds
# the SID of hadrlab2. After a failover back to hadrlab1, the application is refused there.
# Leaves hadrlab1 primary, the user mapped to the SID of hadrlab2: 04-copy-with-sid.sh repairs
# it. Run after 02-login-without-sid.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
app() {
    $engine exec -i -e SQLCMDPASSWORD='M11-App-2026!' "$1" /opt/mssql-tools18/bin/sqlcmd \
        -S 127.0.0.1 -U m11_app -C -b -h -1 -W -d m11_registration \
        -Q "SET NOCOUNT ON; SELECT CONCAT(N'  connected to ', @@SERVERNAME, N', database ', DB_NAME());" 2>&1 \
        | grep -v '^ *$' | sed 's/^Sqlcmd: Error: Microsoft ODBC Driver 18 for SQL Server : /  /' || true
}
usid() {  # the SID of the user m11_app, read in the database on the primary
    sql $1 -h -1 -d m11_registration -Q "SET NOCOUNT ON; SELECT CONCAT(N'  user m11_app, SID ',
        CONVERT(varchar(40), sid, 1), N', login of ', @@SERVERNAME, N' with that SID: ',
        ISNULL(SUSER_SNAME(sid), N'none')) FROM sys.database_principals WHERE name = N'm11_app';"
}
echo "== hadrlab2: ALTER USER m11_app WITH LOGIN = m11_app"
sql hadrlab2 -d m11_registration -Q "ALTER USER m11_app WITH LOGIN = m11_app;" | { grep -v 'Changed database' || true; }
usid hadrlab2
app hadrlab2
echo
echo "== the planned failover of AgPacha back to hadrlab1"
bash setup/ag-failover.sh AgPacha hadrlab1 | tail -1 | sed 's/^/  /'
echo
echo "== the application, on hadrlab1"
usid hadrlab1
app hadrlab1
