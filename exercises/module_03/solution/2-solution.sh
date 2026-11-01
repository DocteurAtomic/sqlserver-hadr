#!/usr/bin/env bash
# Exercise of module 3, a solution. Run after 1-start.sh. A full backup of ex_inscriptions
# starts its log chain, then the database joins AgPacha on hadrlab1, and the automatic
# seeding copies it to hadrlab2 and hadrlab3 (their GRANT CREATE ANY DATABASE, given when
# they joined the group, still holds). Waits, at most five minutes, until both copies are
# caught up. Other solutions hold too: check.sh reads the state.
set -euo pipefail
cd "$(dirname "$0")/../../.."
. setup/lib.sh
sql hadrlab1 <<'SQL'
SET NOCOUNT ON;
BACKUP DATABASE ex_inscriptions TO DISK = N'/var/opt/mssql/share/ex_inscriptions/ex_inscriptions-full.bak'
    WITH INIT, COMPRESSION, CHECKSUM;
ALTER AVAILABILITY GROUP AgPacha ADD DATABASE ex_inscriptions;
SQL
wait_ag_database hadrlab1 AgPacha ex_inscriptions 300
