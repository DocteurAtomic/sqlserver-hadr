#!/usr/bin/env bash
# Module 2, setup. Builds on hadrlab1 the database m02_registration, a copy of
# PachadataTraining in the full recovery model that stands for the registration site, with
# its full backup on the shared volume (/var/opt/mssql/share/m02_registration-full.bak), the
# procedure dbo.m02_register that writes a batch of registrations tagged in OrderReference,
# and the folder of the log backups (/var/opt/mssql/share/logship/m02_registration). Log
# shipping itself is the demo: 01-primary.sql and 02-secondary.sql set it up. Run it again
# to start over; 99-cleanup.sh removes what the module creates.
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
bash demos/module_02/99-cleanup.sh >/dev/null
start=$(date +%s.%N)
sql hadrlab1 <<'SQL' | grep -v 'running the upgrade step'
SET NOCOUNT ON;
-- A copy of PachadataTraining, FULL, with its first full backup (master.dbo.reset_training is
-- created by setup/install.sh).
EXEC master.dbo.reset_training @db = N'm02_registration';
GO
USE m02_registration;
GO
CREATE OR ALTER PROCEDURE dbo.m02_register @rows int, @batch varchar(20)
AS
    INSERT Enrollment.Enrollment (SessionId, ContactId, Discount, Attended, CreationDate,
           OrderReference, AgreementSent, JoiningInstructionsSent, WaitingList)
    SELECT TOP (@rows) SessionId, ContactId, 0, 0, SYSDATETIME(), @batch, 0, 0, 0
    FROM Enrollment.Enrollment
    ORDER BY EnrollmentId;
GO
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/logship/m02_registration';
SELECT name, recovery_model_desc AS recovery_model, state_desc AS state
FROM sys.databases WHERE name = N'm02_registration';
GO
SQL
echo "$(awk -v s=$start -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }') s"
