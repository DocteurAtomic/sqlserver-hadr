#!/usr/bin/env bash
# Clip 5.1: what a readable secondary costs the primary. On hadrlab1, the size of the rows of
# m05_reports.dbo.Enrollment, read in sys.dm_db_index_physical_stats (DETAILED, leaf level).
# First without any readable secondary: hadrlab3 back to ALLOW_CONNECTIONS = NO, the table
# every row updated once a second until no row carries more than its 63 bytes (at most 90
# seconds), then the table rebuilt. Then hadrlab3 in READ_ONLY again: the rows updated once a second until they
# carry the 14 bytes of the row version (at most 90 seconds), and the time it took. Then the
# number of pages. Appends the result to evidence/module_05.md. Leaves hadrlab3 in READ_ONLY.
# Run after 00-setup.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
size() {  # one line: the records and pages of the table on hadrlab1
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'$1: records of ', min_record_size_in_bytes, N' to ', max_record_size_in_bytes, N' bytes, average ',
              FORMAT(avg_record_size_in_bytes, N'0.0'), N', ', record_count, N' records on ', page_count, N' pages')
FROM sys.dm_db_index_physical_stats(DB_ID(N'm05_reports'), OBJECT_ID(N'm05_reports.dbo.Enrollment'), 1, NULL, 'DETAILED')
WHERE index_level = 0;"
}
update_until() {  # updates every row once a second until the largest record has the given size,
                  # at most 90 seconds; prints the time it took
    sql hadrlab1 -h -1 -v WANT="$1" <<'SQL'
SET NOCOUNT ON;
DECLARE @t0 datetime2(3) = SYSDATETIME(), @max int = 0, @n int = 0;
WHILE DATEDIFF(second, @t0, SYSDATETIME()) < 90
BEGIN
    UPDATE m05_reports.dbo.Enrollment SET session_id = session_id + 1;
    SET @n += 1;
    SELECT @max = max_record_size_in_bytes
    FROM sys.dm_db_index_physical_stats(DB_ID(N'm05_reports'), OBJECT_ID(N'm05_reports.dbo.Enrollment'), 1, NULL, 'DETAILED')
    WHERE index_level = 0;
    IF @max = $(WANT) BREAK;
    WAITFOR DELAY '00:00:01';
END;
IF @max <> $(WANT)
    THROW 50000, N'the records do not reach the expected size within 90 seconds', 1;
PRINT CONCAT(N'  ', @n, N' updates of every row, ', FORMAT(DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0, N'0.0'),
             N' s until the largest record is ', @max, N' bytes');
SQL
}
pages() {
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT page_count FROM sys.dm_db_index_physical_stats(DB_ID(N'm05_reports'), OBJECT_ID(N'm05_reports.dbo.Enrollment'), 1, NULL, 'DETAILED') WHERE index_level = 0;" | tr -d '[:space:]'
}
allow() {
    sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha MODIFY REPLICA ON N'hadrlab3' WITH (SECONDARY_ROLE (ALLOW_CONNECTIONS = $1));"
    echo "  hadrlab3: ALLOW_CONNECTIONS = $1"
}
echo "== hadrlab1, no readable secondary"
allow NO
update_until 63
sql hadrlab1 -Q "SET NOCOUNT ON; ALTER INDEX ALL ON m05_reports.dbo.Enrollment REBUILD;"
size "not readable, after an update and a rebuild"
pages0=$(pages)
echo
echo "== hadrlab1, hadrlab3 readable"
allow READ_ONLY
t=$(date +%s)
update_until 77
size "readable, after an update"
delay=$(( $(date +%s) - t ))
pages1=$(pages)
mkdir -p evidence
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 5, hadrlab3 made readable (ALLOW_CONNECTIONS = READ_ONLY): each row updated on the primary went from 63 to 77 bytes (14 bytes of row version), the table from ${pages0} to ${pages1} pages, about ${delay} s after the change, three containers on one host" >> evidence/module_05.md
