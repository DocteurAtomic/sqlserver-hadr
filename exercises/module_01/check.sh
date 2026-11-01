#!/usr/bin/env bash
# Exercise of module 1: checks the choices written in ex_needs.dbo.Choice on hadrlab1.
# It refuses what cannot work with the needs and the edition: a missing database or reason,
# a solution that loses data where the RPO is 0, an Enterprise-only solution on Standard
# edition, two databases in one availability group on Standard edition. It accepts every
# other choice. Exits with 0 when the choices hold, with 1 otherwise, saying what is wrong.
# Usage: ./exercises/module_01/check.sh     (with Podman: ENGINE=podman ...)
set -uo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
query=$(cat <<'SQL'
SET NOCOUNT ON;
DECLARE @r TABLE (n int IDENTITY, line nvarchar(400));
DECLARE @edition varchar(20) = (SELECT edition FROM dbo.Licence);
INSERT @r SELECT CONCAT(N'FAIL ', n.database_name, N': no choice written in dbo.Choice')
FROM dbo.Need AS n WHERE NOT EXISTS (SELECT * FROM dbo.Choice AS c WHERE c.database_name = n.database_name);
INSERT @r SELECT CONCAT(N'FAIL ', database_name, N': the reason is missing or too short (20 characters at least)')
FROM dbo.Choice WHERE LEN(reason) < 20;
INSERT @r SELECT CONCAT(N'FAIL ', c.database_name, N': RPO 0, and ', c.solution,
                        N' loses what the secondary has not received yet')
FROM dbo.Choice AS c JOIN dbo.Need AS n ON n.database_name = c.database_name
WHERE n.rpo_seconds = 0
  AND c.solution IN ('BACKUPS', 'LOG_SHIPPING', 'BASIC_AG_ASYNC', 'AG_ASYNC', 'DISTRIBUTED_AG');
INSERT @r SELECT CONCAT(N'FAIL ', database_name, N': ', solution, N' needs Enterprise edition, PachaData has ', @edition)
FROM dbo.Choice
WHERE @edition = 'Standard' AND solution IN ('AG_SYNC', 'AG_ASYNC', 'DISTRIBUTED_AG');
INSERT @r SELECT CONCAT(N'FAIL group ', group_name, N': ', COUNT(*),
                        N' databases, and a basic availability group holds one database')
FROM dbo.Choice
WHERE @edition = 'Standard' AND solution LIKE '%AG%' AND group_name IS NOT NULL
GROUP BY group_name HAVING COUNT(*) > 1;
INSERT @r SELECT CONCAT(N'FAIL ', database_name, N': an availability group needs a group_name')
FROM dbo.Choice WHERE solution LIKE '%AG%' AND group_name IS NULL;
IF NOT EXISTS (SELECT * FROM @r)
    INSERT @r SELECT CONCAT(N'ok   ', database_name, N': ', solution, ISNULL(N' (' + group_name + N')', N''))
    FROM dbo.Choice ORDER BY database_name;
SELECT line FROM @r ORDER BY n;
SQL
)
db=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT ISNULL(DB_NAME(DB_ID(N'ex_needs')), N'none');" 2>&1)
if [ "$(echo "$db" | tr -d '[:space:]')" != "ex_needs" ]; then
    echo "$db" | grep -v '^none' | head -3
    echo "FAIL ex_needs is missing on hadrlab1: run exercises/module_01/1-start.sql first"; exit 1
fi
out=$(sql hadrlab1 -h -1 -d ex_needs <<< "$query" 2>&1)
rc=$?
echo "$out"
if [ $rc -ne 0 ] || [ -z "$out" ]; then echo "FAIL hadrlab1 does not answer"; exit 1; fi
if echo "$out" | grep -q '^FAIL'; then echo "The choices do not hold yet."; exit 1; fi
echo "The choices hold."
