#!/usr/bin/env bash
# ci: skip (it starts a throwaway container on the network of the host, which Docker Desktop
# does not give: run it by hand, on Linux)
# Clip 5.2: the same redirection seen from the host, as SSMS on your machine would see it. A
# throwaway container of the same image, on the network of the host (--network host), runs
# sqlcmd against 127.0.0.1,14633, the port of hadrlab3 on the host, without the read-only
# intent: SQL Server redirects it to hadrlab1,1433, a name the host cannot resolve, and the
# connection fails. With -K ReadOnly it stays on hadrlab3. Run after 04-read-write-routing.sh,
# with hadrlab3 in ALL (the script sets it, and puts READ_ONLY back at the end).
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
image=$($engine inspect -f '{{.Config.Image}}' hadrlab3)
host() {  # sqlcmd from the host network, at most 20 seconds
    timeout 20 $engine run --rm --network host -e SQLCMDPASSWORD="$($engine exec hadrlab3 printenv SQLCMDPASSWORD)" \
        --entrypoint /opt/mssql-tools18/bin/sqlcmd "$image" -C -l 10 -S 127.0.0.1,${SQLPORT3:-14633} -U sa -h -1 -W "$@" \
        -Q "SET NOCOUNT ON; SELECT CONCAT(@@SERVERNAME, N' ', DB_NAME(), N' ', CONVERT(nvarchar(20), DATABASEPROPERTYEX(DB_NAME(), 'Updateability')))" 2>&1 \
        | grep -v '^ *$' | sed 's/^Sqlcmd: Error: Microsoft ODBC Driver 18 for SQL Server : /  /' || true
}
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = ALL));"
sleep 2
echo "== from the host, 127.0.0.1,${SQLPORT3:-14633} -d m05_reports"
host -d m05_reports
echo
echo "== from the host, 127.0.0.1,${SQLPORT3:-14633} -d m05_reports -K ReadOnly"
host -d m05_reports -K ReadOnly
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY));"
