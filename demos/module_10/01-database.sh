#!/usr/bin/env bash
# Clip 10.1: add a database to the group, remove it, and put it back without a new seeding.
#   1. hadrlab1: ALTER AVAILABILITY GROUP AgPacha ADD DATABASE m10_archive; the copies are
#      seeded (setup/lib.sh wait_ag_database), and the seeding leaves one backup per secondary
#      in msdb on hadrlab1, to a device named by a GUID.
#   2. hadrlab1: REMOVE DATABASE m10_archive; on hadrlab1 the database stays online, outside the
#      group; on hadrlab2 and hadrlab3 the copy is read every second, at most a minute, until
#      it says RESTORING: until then it is still ONLINE, read-only, and still in the group.
#   3. hadrlab1: 50 rows written after the removal, then a log backup on the shared volume;
#      hadrlab2 and hadrlab3: RESTORE LOG ... WITH NORECOVERY of that backup.
#   4. hadrlab1: ADD DATABASE m10_archive again. The replicas are in automatic seeding: each
#      secondary joins its RESTORING copy by itself (an explicit SET HADR AVAILABILITY GROUP
#      would get Msg 41145, "already joined"), and no new seeding backup appears.
# Appends the time the removed copies stayed ONLINE to evidence/module_10.md. Run after
# 00-setup.sh.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
mkdir -p evidence
seedings() {  # the seeding backups of m10_archive in msdb of hadrlab1
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  seeding backups of m10_archive in msdb of hadrlab1: ', COUNT(*))
FROM msdb.dbo.backupset AS b JOIN msdb.dbo.backupmediafamily AS m ON m.media_set_id = b.media_set_id
WHERE b.database_name = N'm10_archive' AND TRY_CAST(m.physical_device_name AS uniqueidentifier) IS NOT NULL;"
}
copies() {  # the state of the copies of m10_archive, read on each instance
    for n in $nodes; do
        sql $n -h -1 -Q "SET NOCOUNT ON;
SELECT CONCAT(N'  ', @@SERVERNAME, N': ', d.state_desc COLLATE DATABASE_DEFAULT, N', ', CAST(DATABASEPROPERTYEX(d.name, 'Updateability') AS nvarchar(20)),
              N', ', ISNULL(N'in the group, ' + rs.synchronization_state_desc COLLATE DATABASE_DEFAULT, N'outside the group'))
FROM sys.databases AS d
LEFT JOIN sys.dm_hadr_database_replica_states AS rs ON rs.database_id = d.database_id AND rs.is_local = 1
WHERE d.name = N'm10_archive';"
    done
}
echo "== 1. hadrlab1: ADD DATABASE m10_archive"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha ADD DATABASE m10_archive;"
wait_ag_database hadrlab1 AgPacha m10_archive 120
copies
seedings
echo
echo "== 2. hadrlab1: REMOVE DATABASE m10_archive, then the copies, every second"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha REMOVE DATABASE m10_archive;"
t0=$(date +%s.%N)
last=""
for i in $(seq 1 60); do
    now=$(for n in hadrlab2 hadrlab3; do
        sql $n -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(@@SERVERNAME, N' ', state_desc COLLATE DATABASE_DEFAULT, N' ',
            IIF(EXISTS (SELECT * FROM sys.dm_hadr_database_replica_states WHERE database_id = DB_ID(N'm10_archive')),
                N'in the group', N'outside the group')) FROM sys.databases WHERE name = N'm10_archive';"
    done | tr -s '\n' ' ')
    t=$(awk -v s=$t0 -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }')
    [ "$now" != "$last" ] && echo "  +$t s: $now"
    last=$now
    case $now in *hadrlab2\ RESTORING*hadrlab3\ RESTORING*) break ;; esac
    sleep 1
done
case $last in *hadrlab2\ RESTORING*hadrlab3\ RESTORING*) ;; *) echo "the copies are not RESTORING a minute after the removal" >&2; exit 1 ;; esac
copies
echo "- $(date -u '+%Y-%m-%d %H:%M') UTC, module 10, REMOVE DATABASE: the copies on hadrlab2 and hadrlab3 stayed ONLINE and in the group for less than $t s, then RESTORING; three containers on one host" >> evidence/module_10.md
echo
echo "== 3. hadrlab1: 50 rows, then BACKUP LOG; hadrlab2 and hadrlab3: RESTORE LOG WITH NORECOVERY"
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON;
INSERT m10_archive.dbo.Archive (label) SELECT TOP (50) 'after the removal' FROM sys.all_objects;
BACKUP LOG m10_archive TO DISK = N'/var/opt/mssql/share/m10/m10_archive-back.trn' WITH INIT;" | grep -v '^Processed'
for n in hadrlab2 hadrlab3; do
    sql $n -h -1 -Q "RESTORE LOG m10_archive FROM DISK = N'/var/opt/mssql/share/m10/m10_archive-back.trn' WITH NORECOVERY;" \
        | grep -v '^Processed' | sed "s/^/  $n: /"
done
echo
echo "== 4. hadrlab1: ADD DATABASE m10_archive again"
sql hadrlab1 -Q "ALTER AVAILABILITY GROUP AgPacha ADD DATABASE m10_archive;"
sleep 2
echo "  hadrlab2: ALTER DATABASE m10_archive SET HADR AVAILABILITY GROUP = AgPacha"
sql hadrlab2 -Q "ALTER DATABASE m10_archive SET HADR AVAILABILITY GROUP = AgPacha;" 2>&1 | sed 's/^/  /' || true
wait_ag_database hadrlab1 AgPacha m10_archive 120
copies
seedings
sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'  rows of m10_archive.dbo.Archive on hadrlab1: ', COUNT(*)) FROM m10_archive.dbo.Archive;"
