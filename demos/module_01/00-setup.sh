#!/usr/bin/env bash
# Module 1, setup. Builds on hadrlab1 the database m01_registration, a copy of
# PachadataTraining that stands for the registration site, with a day of backups played
# fast: one log backup every five seconds instead of every fifteen minutes. It takes about
# half a minute. Everything goes to /var/opt/mssql/share/m01 (the shared volume, which
# outlives a lost instance): after the full backup that reset_training takes, a log backup,
# a differential, two more log backups. Between them, batches of new registrations, tagged in OrderReference
# ('m01 batch 1' to 'm01 batch 5'). The fifth batch comes after the last log backup: no
# backup holds it. Run it again to start over; 99-cleanup.sh removes what it creates.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash demos/module_01/99-cleanup.sh >/dev/null
start=$(date +%s.%N)
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/m01';
-- A copy of PachadataTraining in the full recovery model, with its first full backup, written
-- to /var/opt/mssql/share/m01_registration-full.bak (master.dbo.reset_training is created by
-- setup/install.sh).
EXEC master.dbo.reset_training @db = N'm01_registration';
GO
USE m01_registration;
GO
CREATE OR ALTER PROCEDURE dbo.m01_register @rows int, @batch varchar(20)
AS
    INSERT Enrollment.Enrollment (SessionId, ContactId, Discount, Attended, CreationDate,
           OrderReference, AgreementSent, JoiningInstructionsSent, WaitingList)
    SELECT TOP (@rows) SessionId, ContactId, 0, 0, SYSDATETIME(), @batch, 0, 0, 0
    FROM Enrollment.Enrollment
    ORDER BY EnrollmentId;
GO
EXEC dbo.m01_register 120, 'm01 batch 1';
WAITFOR DELAY '00:00:05';
BACKUP LOG m01_registration TO DISK = N'/var/opt/mssql/share/m01/m01_registration_log1.trn'
    WITH INIT, COMPRESSION, CHECKSUM;
EXEC dbo.m01_register 80, 'm01 batch 2';
WAITFOR DELAY '00:00:05';
BACKUP DATABASE m01_registration TO DISK = N'/var/opt/mssql/share/m01/m01_registration_diff1.bak'
    WITH DIFFERENTIAL, INIT, COMPRESSION, CHECKSUM;
EXEC dbo.m01_register 60, 'm01 batch 3';
WAITFOR DELAY '00:00:05';
BACKUP LOG m01_registration TO DISK = N'/var/opt/mssql/share/m01/m01_registration_log2.trn'
    WITH INIT, COMPRESSION, CHECKSUM;
EXEC dbo.m01_register 50, 'm01 batch 4';
WAITFOR DELAY '00:00:05';
BACKUP LOG m01_registration TO DISK = N'/var/opt/mssql/share/m01/m01_registration_log3.trn'
    WITH INIT, COMPRESSION, CHECKSUM;
-- After the last log backup: these rows are only in the database and in its log.
EXEC dbo.m01_register 37, 'm01 batch 5';
SELECT OrderReference AS batch, COUNT(*) AS registrations
FROM Enrollment.Enrollment WHERE OrderReference LIKE 'm01 batch%'
GROUP BY OrderReference ORDER BY batch;
GO
SQL
echo "$(awk -v s=$start -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }') s"
