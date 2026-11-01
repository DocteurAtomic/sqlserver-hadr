#!/usr/bin/env bash
# Writes one row every half second into m13_registration through the virtual address, from pc3
# (a client inside the lab network), for a number of seconds, and prints one line per attempt:
# the time, then the instance that committed the row, or the error. A failover shows as the
# lines in error between the last row of the old primary and the first row of the new one.
# The rows have the email 'writer@pachadata.example' and the server that committed them.
# Usage: ./extra/pacemaker/writer.sh [seconds] [label]     (default 60 seconds)
set -uo pipefail
cd "$(dirname "$0")"
. ./lib.sh
podman exec -i -e SECONDS_MAX="${1:-60}" -e LABEL="${2:-writer}" -e VIP=$vip -e DB=$db pc3 bash <<'IN'
end=$(( $(date +%s) + SECONDS_MAX ))
while [ "$(date +%s)" -lt "$end" ]; do
    out=$(/opt/mssql-tools18/bin/sqlcmd -C -l 2 -t 3 -S "$VIP" -U sa -d "$DB" -h -1 -W -b -Q "SET NOCOUNT ON;
        INSERT dbo.Registration (email) OUTPUT inserted.server VALUES ('$LABEL@pachadata.example');" 2>&1 \
        | grep -v '^ *$' | tail -1 | sed 's/^Sqlcmd: Error: Microsoft ODBC Driver 18 for SQL Server : //' | cut -c1-90)
    echo "$(date +%T.%3N) $out"
    sleep 0.5
done
IN
