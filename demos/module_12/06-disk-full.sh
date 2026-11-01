#!/usr/bin/env bash
# Clip 12.3: the disk of a secondary fills up. No host disk is filled: the copy of hadrlab2 lives
# in /dev/shm of its container, a tmpfs of 64 MB that Docker and Podman give every container by
# default, and a filler file there leaves it about 6 MB free. On the primary, the log of the
# database is capped by MAXSIZE (24 MB), so that the primary's log fills up too, in seconds;
# the sizes are chosen so that the repaired copy, data and log grown like the primary's, fits
# again in the 64 MB once the filler is gone.
#   1. m12_disk on hadrlab1 (data and log 8 MB, growth 8 MB, log at most 24 MB), restored on
#      hadrlab2 into /dev/shm/m12 (WITH MOVE), then the group m12_disk, hadrlab1 and hadrlab2 in
#      synchronous commit, manual seeding; then the filler on hadrlab2;
#   2. batches of 500 rows of 4 KB on hadrlab1, each followed by a log backup: the size of the
#      log and why it is kept, the state of the copy of hadrlab2; until the primary refuses two
#      batches (Msg 9002) or thirty batches;
#   3. what hadrlab2 says: its copy, its error log, its disk;
#   4. the repair, in order: room on the secondary (the filler deleted), the copy resumed there,
#      then a log backup on the primary, which frees its log, and a batch that passes again.
# The group m12_disk stays (99-cleanup.sh removes it). Run after 00-setup.sh; it removes what a
# previous run of it left.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash setup/ag-remove.sh m12_disk >/dev/null
for n in hadrlab1 hadrlab2; do
    sql $n -h -1 -Q "SET NOCOUNT ON; IF DB_ID(N'm12_disk') IS NOT NULL BEGIN
        IF DATABASEPROPERTYEX(N'm12_disk', 'Status') = N'ONLINE' ALTER DATABASE m12_disk SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        DROP DATABASE m12_disk; END;"
done
$engine exec hadrlab2 sh -c 'rm -rf /dev/shm/m12 && mkdir /dev/shm/m12'
since=$(sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONVERT(char(23), GETDATE(), 121);" | tr -d '\r')
shm() { $engine exec hadrlab2 df -m /dev/shm | awk 'NR == 2 { print "  hadrlab2 /dev/shm: " $2 " MB, " $3 " used, " $4 " free" }'; }
echo "== 1. hadrlab1: m12_disk, its backups; hadrlab2: the copy restored into /dev/shm/m12"
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/m12';
CREATE DATABASE m12_disk
    ON (NAME = m12_disk, FILENAME = N'/var/opt/mssql/data/m12_disk.mdf', SIZE = 8MB, FILEGROWTH = 8MB)
    LOG ON (NAME = m12_disk_log, FILENAME = N'/var/opt/mssql/data/m12_disk_log.ldf',
            SIZE = 8MB, FILEGROWTH = 8MB, MAXSIZE = 24MB);
ALTER DATABASE m12_disk SET RECOVERY FULL;
GO
CREATE TABLE m12_disk.dbo.Batch (id int IDENTITY PRIMARY KEY, batch int NOT NULL, payload char(4000) NOT NULL DEFAULT '');
BACKUP DATABASE m12_disk TO DISK = N'/var/opt/mssql/share/m12/m12_disk.bak' WITH INIT, CHECKSUM;
BACKUP LOG m12_disk TO DISK = N'/var/opt/mssql/share/m12/m12_disk.trn' WITH INIT, CHECKSUM;
SQL
sql hadrlab2 -h -1 <<'SQL'
SET NOCOUNT ON;
RESTORE DATABASE m12_disk FROM DISK = N'/var/opt/mssql/share/m12/m12_disk.bak'
    WITH NORECOVERY, MOVE N'm12_disk' TO N'/dev/shm/m12/m12_disk.mdf',
                     MOVE N'm12_disk_log' TO N'/dev/shm/m12/m12_disk_log.ldf';
RESTORE LOG m12_disk FROM DISK = N'/var/opt/mssql/share/m12/m12_disk.trn' WITH NORECOVERY;
SQL
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
CREATE AVAILABILITY GROUP m12_disk
WITH (CLUSTER_TYPE = NONE)
FOR DATABASE m12_disk
REPLICA ON
    N'hadrlab1' WITH (ENDPOINT_URL = N'tcp://hadrlab1:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
                      FAILOVER_MODE = MANUAL, SEEDING_MODE = MANUAL),
    N'hadrlab2' WITH (ENDPOINT_URL = N'tcp://hadrlab2:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
                      FAILOVER_MODE = MANUAL, SEEDING_MODE = MANUAL);
SQL
join_ag hadrlab2 m12_disk
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; ALTER DATABASE m12_disk SET HADR AVAILABILITY GROUP = m12_disk;"
wait_ag_database hadrlab1 m12_disk m12_disk 60 | sed 's/^/  /'
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'  hadrlab2: ', name, N' ', physical_name, N' ', size / 128, N' MB')
    FROM sys.master_files WHERE database_id = DB_ID(N'm12_disk') ORDER BY file_id;"
# The filler: what a forgotten export on the disk of the secondary would be. It leaves 6 MB free.
free=$($engine exec hadrlab2 df -m /dev/shm | awk 'NR == 2 { print $4 }')
$engine exec hadrlab2 sh -c "head -c $(( (free - 6) * 1048576 )) /dev/zero > /dev/shm/m12/old-export.dat"
echo "  hadrlab2: /dev/shm/m12/old-export.dat, $((free - 6)) MB"
shm
echo
echo "== 2. hadrlab1: batches of 500 rows of 4 KB, a log backup after each"
echo "  batch log_used_mb log_size_mb data_mb log_reuse_wait copy_of_hadrlab2"
# The messages of each BACKUP LOG ("Processed ... pages") are left out.
sql hadrlab1 -h -1 2>&1 <<'SQL' | { grep -v -e '^Processed ' -e '^BACKUP LOG successfully' || true; }
SET NOCOUNT ON;
DECLARE @b int = 1, @refused int = 0, @err nvarchar(300), @line nvarchar(400);
WHILE @b <= 30 AND @refused < 2
BEGIN
    SET @err = NULL;
    BEGIN TRY
        INSERT m12_disk.dbo.Batch (batch) SELECT TOP (500) @b FROM sys.all_objects;
    END TRY
    BEGIN CATCH
        SET @err = CONCAT(N'Msg ', ERROR_NUMBER(), N' ', LEFT(ERROR_MESSAGE(), 160));
        SET @refused += 1;
    END CATCH;
    BACKUP LOG m12_disk TO DISK = N'/var/opt/mssql/share/m12/m12_disk-log.trn' WITH INIT;
    SELECT @line = CONCAT(N'  ', @b, N' ',
        FORMAT(u.used_log_space_in_bytes / 1048576.0, N'0'), N' ', FORMAT(u.total_log_size_in_bytes / 1048576.0, N'0'), N' ',
        (SELECT size / 128 FROM m12_disk.sys.database_files WHERE type = 0), N' ', d.log_reuse_wait_desc, N' ',
        (SELECT CONCAT(s.synchronization_state_desc, N' ', ISNULL(s.suspend_reason_desc, N''))
         FROM sys.dm_hadr_database_replica_states AS s WHERE s.database_id = d.database_id AND s.is_local = 0))
    FROM sys.databases AS d CROSS APPLY m12_disk.sys.dm_db_log_space_usage AS u
    WHERE d.name = N'm12_disk';
    PRINT @line;
    IF @err IS NOT NULL PRINT CONCAT(N'    batch ', @b, N': ', @err);
    SET @b += 1;
END;
SQL
echo
echo "== 3. hadrlab2: its copy, its error log, its disk"
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'  m12_disk ', d.state_desc COLLATE DATABASE_DEFAULT, N', ', s.synchronization_state_desc, N', ',
    ISNULL(s.suspend_reason_desc, N'not suspended')) FROM sys.databases AS d
    JOIN sys.dm_hadr_database_replica_states AS s ON s.database_id = d.database_id AND s.is_local = 1 WHERE d.name = N'm12_disk';"
sql hadrlab2 -h -1 -v SINCE="$since" <<'SQL'
SET NOCOUNT ON;
DECLARE @l TABLE (logdate datetime, process nvarchar(50), txt nvarchar(4000));
INSERT @l EXEC sys.xp_readerrorlog 0, 1, N'm12_disk';
INSERT @l EXEC sys.xp_readerrorlog 0, 1, N'Error:';
-- From the first operating system error on: the restore and the join come before.
SELECT x.line FROM (
    SELECT DISTINCT CONCAT(N'  ', CONVERT(char(12), logdate, 114), N' ', LEFT(txt, 170)) AS line, logdate
    FROM @l
    WHERE logdate >= (SELECT MIN(logdate) FROM @l WHERE logdate >= '$(SINCE)' AND txt LIKE N'%Operating system error%')
      AND txt NOT LIKE N'%DebugTraceVarArgs%' AND txt NOT LIKE N'Parallel redo%') AS x
ORDER BY x.logdate, x.line;
SQL
shm
echo
echo "== 4. the repair: hadrlab2 first"
$engine exec hadrlab2 rm /dev/shm/m12/old-export.dat
echo "  hadrlab2: old-export.dat deleted"
shm
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; ALTER DATABASE m12_disk SET HADR RESUME;"
echo "  hadrlab2: ALTER DATABASE m12_disk SET HADR RESUME"
wait_ag_database hadrlab1 m12_disk m12_disk 120 | sed 's/^/  /'
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'  hadrlab2: m12_disk ', d.state_desc COLLATE DATABASE_DEFAULT, N', ', s.synchronization_state_desc)
    FROM sys.databases AS d JOIN sys.dm_hadr_database_replica_states AS s ON s.database_id = d.database_id AND s.is_local = 1
    WHERE d.name = N'm12_disk';"
echo "== 4. then hadrlab1: a log backup, and a batch"
sql hadrlab1 -h -1 <<'SQL' | { grep -v -e '^Processed ' -e '^BACKUP LOG successfully' || true; }
SET NOCOUNT ON;
DECLARE @i int = 0;
-- The secondary reports how far it has redone with some delay (module 4): a few tries.
WHILE @i < 10 AND (SELECT log_reuse_wait_desc FROM sys.databases WHERE name = N'm12_disk') <> N'NOTHING'
BEGIN
    BACKUP LOG m12_disk TO DISK = N'/var/opt/mssql/share/m12/m12_disk-log.trn' WITH INIT;
    SET @i += 1;
    IF (SELECT log_reuse_wait_desc FROM sys.databases WHERE name = N'm12_disk') <> N'NOTHING' WAITFOR DELAY '00:00:02';
END;
SELECT CONCAT(N'  ', @i, N' log backup(s): log ', FORMAT(u.used_log_space_in_bytes / 1048576.0, N'0.0'), N' MB used of ',
              FORMAT(u.total_log_size_in_bytes / 1048576.0, N'0'), N', ', d.log_reuse_wait_desc)
FROM sys.databases AS d CROSS APPLY m12_disk.sys.dm_db_log_space_usage AS u WHERE d.name = N'm12_disk';
DECLARE @t0 datetime2(3) = SYSDATETIME();
INSERT m12_disk.dbo.Batch (batch) SELECT TOP (500) 99 FROM sys.all_objects;
SELECT CONCAT(N'  batch 99: 500 rows committed in ', DATEDIFF(millisecond, @t0, SYSDATETIME()), N' ms; ',
              (SELECT COUNT(*) FROM m12_disk.dbo.Batch), N' rows in dbo.Batch');
SQL
