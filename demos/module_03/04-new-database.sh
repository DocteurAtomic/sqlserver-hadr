#!/usr/bin/env bash
# Clip 3.2: m03_signup, a new database in the full recovery model that was never backed up,
# offered to AgPacha. ADD DATABASE fails with Msg 1475, whose text asks for a log backup;
# the log backup it asks for fails in turn (Msg 4214): the log chain has not started, the
# database is still in pseudo-simple mode. Nothing changes on the lab; what the database
# needs is the subject of the exercise. Run after 03-join.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
echo "hadrlab1, m03_signup before:"
sql hadrlab1 -Q "SET NOCOUNT ON; SELECT d.name, d.recovery_model_desc AS recovery_model,
    ISNULL(CAST(r.last_log_backup_lsn AS varchar(30)), 'NULL') AS last_log_backup_lsn
    FROM sys.databases AS d JOIN sys.database_recovery_status AS r ON r.database_id = d.database_id
    WHERE d.name = N'm03_signup';"
echo
echo "1. ADD DATABASE:"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha ADD DATABASE m03_signup;" \
    || echo "(refused, exit code $?)"
echo
echo "2. The log backup that the message asks for:"
sql hadrlab1 -Q "BACKUP LOG m03_signup TO DISK = N'/dev/null';" \
    || echo "(refused, exit code $?)"
echo
echo "hadrlab1, the databases of AgPacha after:"
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(g.name, ': ', d.database_name)
    FROM sys.availability_databases_cluster AS d JOIN sys.availability_groups AS g ON g.group_id = d.group_id;"
