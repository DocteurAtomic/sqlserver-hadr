#!/usr/bin/env bash
# Clip 11.1: the login created again by hand on hadrlab2, same name, same password, but a new SID.
# The application now reaches the instance, and is refused at the door of the database (Error
# 18456, State 38): the user m11_app of m11_registration holds the SID of the login of hadrlab1,
# and no login of hadrlab2 has that SID. The query lists the users of the database whose SID no
# login of the instance holds: the orphan users. Leaves hadrlab2 primary. Run after
# 01-login-missing.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
app() {
    $engine exec -i -e SQLCMDPASSWORD='M11-App-2026!' "$1" /opt/mssql-tools18/bin/sqlcmd \
        -S 127.0.0.1 -U m11_app -C -b -h -1 -W "${@:2}" \
        -Q "SET NOCOUNT ON; SELECT CONCAT(N'  connected to ', @@SERVERNAME, N', database ', DB_NAME());" 2>&1 \
        | grep -v '^ *$' | sed 's/^Sqlcmd: Error: Microsoft ODBC Driver 18 for SQL Server : /  /' || true
}
echo "== hadrlab2: CREATE LOGIN m11_app, the same password"
sql hadrlab2 -Q "IF SUSER_ID(N'm11_app') IS NOT NULL DROP LOGIN m11_app;
CREATE LOGIN m11_app WITH PASSWORD = N'M11-App-2026!', CHECK_POLICY = OFF;"
echo
echo "== the application, on hadrlab2, without a database, then in m11_registration"
app hadrlab2
app hadrlab2 -d m11_registration
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; DECLARE @l TABLE (logdate datetime, process nvarchar(50), txt nvarchar(4000));
INSERT @l EXEC sys.xp_readerrorlog 0, 1, N'm11_app', N'explicitly';
SELECT TOP (1) CONCAT(N'  error log: ', txt) FROM @l ORDER BY logdate DESC;" | grep -v '^ *$'
echo
echo "== the SID of the login m11_app, on each instance"
for n in $nodes; do
    sql $n -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'  ', @@SERVERNAME, N': ',
        ISNULL((SELECT CONVERT(varchar(40), sid, 1) FROM sys.server_principals WHERE name = N'm11_app'), N'no login m11_app'));"
done
echo
echo "== hadrlab2, m11_registration: the users whose SID no login of the instance holds"
sql hadrlab2 -d m11_registration -Q "SET NOCOUNT ON;
SELECT dp.name AS orphan_user, CONVERT(varchar(40), dp.sid, 1) AS user_sid, dp.type_desc
FROM sys.database_principals AS dp
WHERE dp.type = 'S' AND dp.authentication_type_desc = N'INSTANCE'
  AND NOT EXISTS (SELECT * FROM sys.server_principals AS sp WHERE sp.sid = dp.sid);"
