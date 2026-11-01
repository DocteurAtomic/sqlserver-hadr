#!/usr/bin/env bash
# Clip 11.1: the copy of the login, with its SID and its password hash. On hadrlab1, the primary,
# the user is first mapped back to the login of hadrlab1 (ALTER USER ... WITH LOGIN), which gives
# it back its original SID. Then the statement that recreates the login identically is built
# from sys.sql_logins on hadrlab1: CREATE LOGIN ... WITH PASSWORD = <hash> HASHED, SID = <sid>,
# what sp_help_revlogin or Copy-DbaLogin (dbatools) generate. It is run on hadrlab2 and hadrlab3,
# after dropping the login of 02-login-without-sid.sh. The password itself never appears. Then
# the failover to hadrlab2: the application connects, with nothing changed in the database.
# Leaves hadrlab2 primary. Run after 03-remap.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
app() {
    $engine exec -i -e SQLCMDPASSWORD='M11-App-2026!' "$1" /opt/mssql-tools18/bin/sqlcmd \
        -S 127.0.0.1 -U m11_app -C -b -h -1 -W -d m11_registration \
        -Q "SET NOCOUNT ON; SELECT CONCAT(N'  connected to ', @@SERVERNAME, N' as ', SUSER_SNAME(), N', ', COUNT(*), N' registrations read') FROM dbo.Registration;" 2>&1 \
        | grep -v '^ *$' | sed 's/^Sqlcmd: Error: Microsoft ODBC Driver 18 for SQL Server : /  /' || true
}
echo "== hadrlab1: the user back on the login of hadrlab1"
sql hadrlab1 -d m11_registration -Q "ALTER USER m11_app WITH LOGIN = m11_app;" | { grep -v 'Changed database' || true; }
app hadrlab1
echo
echo "== hadrlab1: the statement that recreates the login, built from sys.sql_logins"
stmt=$(sql hadrlab1 -h -1 <<'SQL' | tr -d '\r' | grep -v '^ *$'
SET NOCOUNT ON;
DECLARE @s nvarchar(max);
SELECT @s = CONCAT(N'CREATE LOGIN ', QUOTENAME(name),
    N' WITH PASSWORD = ', CONVERT(nvarchar(max), CAST(LOGINPROPERTY(name, 'PasswordHash') AS varbinary(256)), 1),
    N' HASHED, SID = ', CONVERT(nvarchar(max), sid, 1),
    N', DEFAULT_DATABASE = ', QUOTENAME(default_database_name),
    N', CHECK_POLICY = ', IIF(is_policy_checked = 1, N'ON', N'OFF'),
    N', CHECK_EXPIRATION = ', IIF(is_expiration_checked = 1, N'ON', N'OFF'), N';')
FROM sys.sql_logins WHERE name = N'm11_app';
PRINT @s;
SQL
)
[ -n "$stmt" ] || { echo "no login m11_app on hadrlab1" >&2; exit 1; }
echo "  $stmt"
echo
echo "== hadrlab2 and hadrlab3: the login dropped, then created by that statement"
for n in hadrlab2 hadrlab3; do
    sql $n -Q "IF SUSER_ID(N'm11_app') IS NOT NULL DROP LOGIN m11_app; $stmt"
done
for n in $nodes; do
    sql $n -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'  ', @@SERVERNAME, N': ',
        ISNULL((SELECT CONVERT(varchar(40), sid, 1) FROM sys.server_principals WHERE name = N'm11_app'), N'no login m11_app'));"
done
echo
echo "== the planned failover of AgPacha to hadrlab2"
bash setup/ag-failover.sh AgPacha hadrlab2 | tail -1 | sed 's/^/  /'
echo
echo "== the application, on hadrlab2"
app hadrlab2
