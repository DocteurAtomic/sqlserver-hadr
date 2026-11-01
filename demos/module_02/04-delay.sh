#!/usr/bin/env bash
# ci: skip (it waits for the schedules of the Agent, up to five minutes per try)
# Clip 2.2: the delay of log shipping, measured. Writes one registration on hadrlab1, then
# reads hadrlab2 every two seconds until the row is there, at most 300 s, and prints the
# seconds it took. Without a job run by hand, only the schedules move it: the delay is the
# wait for the next log backup, then for the copy, then for the restore. Each try is
# appended to evidence/module_02.md with its schedules. Run after 03-ship-by-hand.sh.
# Usage: ./demos/module_02/04-delay.sh [tries]     (3 by default)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
tries=${1:-3}
schedules=$(sql hadrlab2 -h -1 -s ' ' <<'SQL'
SET NOCOUNT ON;
SELECT STRING_AGG(CONCAT(REPLACE(REPLACE(j.name, N'_m02_registration', N''), N'LS', N''), N' at :',
                         RIGHT(CONCAT(N'0', sc.active_start_time % 100), 2)), N', ')
       WITHIN GROUP (ORDER BY j.name)
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobschedules AS js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules AS sc ON sc.schedule_id = js.schedule_id
WHERE j.name IN (N'LSCopy_m02_registration', N'LSRestore_m02_registration');
SQL
)
echo "Backup every minute at :00 on hadrlab1; on hadrlab2, $schedules (seconds of each minute)"
mkdir -p evidence
for i in $(seq 1 "$tries"); do
    label="m02 delay $(date -u +%H%M%S)"
    written=$(sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; EXEC m02_registration.dbo.m02_register 1, '$label';
                                     SELECT CONVERT(varchar(8), SYSDATETIME(), 108);" | tr -d '[:space:]')
    t0=$(date +%s)
    while :; do
        n=$(sql hadrlab2 -h -1 -Q "SET NOCOUNT ON;
            IF DATABASEPROPERTYEX(N'm02_registration', 'Status') = N'ONLINE'
                SELECT COUNT(*) FROM m02_registration.Enrollment.Enrollment WHERE OrderReference = '$label';
            ELSE SELECT 0;" 2>/dev/null | tr -d '[:space:]' || echo 0)
        s=$(( $(date +%s) - t0 ))
        if [ "$n" = "1" ]; then break; fi
        if [ $s -ge 300 ]; then
            echo "try $i: the row written at $written is not on hadrlab2 after 300 s: are the jobs enabled?"
            exit 1
        fi
        sleep 2
    done
    echo "try $i: written on hadrlab1 at $written UTC, readable on hadrlab2 after $s s"
    echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 2, log shipping hadrlab1 to hadrlab2 (backup at :00, $schedules, every minute, three containers on one host): a row written at $written UTC readable on the secondary after $s s" >> evidence/module_02.md
    # The next try starts at another second of the minute.
    if [ "$i" -lt "$tries" ]; then sleep $(( 7 + i * 11 )); fi
done
