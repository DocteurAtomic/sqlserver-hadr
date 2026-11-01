#!/usr/bin/env bash
# Clip 11.1: the application's login after a failover. On hadrlab1, the primary, the
# application connects as m11_app and reads m11_registration, and the job m11_heartbeat runs.
# Then a planned failover of AgPacha to hadrlab2 (setup/ag-failover.sh, module 6), and the
# application tries again on hadrlab2, the new primary: "Login failed", and the error log of
# hadrlab2 says why (Error 18456, State 5: no login of that name). The login was created on
# hadrlab1 only; the database, its user included, has moved, the login has not. Leaves hadrlab2
# primary. Run after 00-setup.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
app() {  # connects as m11_app from inside the container, with its password, to a database
    $engine exec -i -e SQLCMDPASSWORD='M11-App-2026!' "$1" /opt/mssql-tools18/bin/sqlcmd \
        -S 127.0.0.1 -U m11_app -C -b -h -1 -W -d m11_registration \
        -Q "SET NOCOUNT ON; SELECT CONCAT(N'  connected to ', @@SERVERNAME, N' as ', SUSER_SNAME(), N', ', COUNT(*), N' registrations read') FROM dbo.Registration;" 2>&1 \
        | grep -v '^ *$' | sed 's/^Sqlcmd: Error: Microsoft ODBC Driver 18 for SQL Server : /  /' || true
}
echo "== the application, on hadrlab1"
app hadrlab1
run_job hadrlab1 m11_heartbeat 60 | grep -v 'started successfully' | sed 's/^/  /'
echo
echo "== the planned failover of AgPacha to hadrlab2"
bash setup/ag-failover.sh AgPacha hadrlab2 | tail -1 | sed 's/^/  /'
echo
echo "== the application, on hadrlab2"
app hadrlab2
echo
echo "== hadrlab2, its error log"
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; DECLARE @l TABLE (logdate datetime, process nvarchar(50), txt nvarchar(4000));
INSERT @l EXEC sys.xp_readerrorlog 0, 1, N'm11_app';
INSERT @l EXEC sys.xp_readerrorlog 0, 1, N'18456';
SELECT TOP (2) CONCAT(N'  ', txt) FROM @l ORDER BY logdate DESC, IIF(txt LIKE N'Error:%', 0, 1);" | grep -v '^ *$'
