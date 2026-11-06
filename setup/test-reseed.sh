#!/usr/bin/env bash
# Checks that wait_ag_database (setup/lib.sh) seeds again a copy whose automatic seeding
# stopped, the way the CI met it in module 4: a copy left in RESTORING outside the group on a
# secondary, which SQL Server does not seed again by itself. Creates a small database on
# hadrlab1 and a group AgReseed for it, takes the copy of hadrlab2 out of the group with
# SET HADR OFF (it stays in RESTORING), then waits: the wait must drop the copy, start a new
# seeding and see the copy synchronized. Removes the group and the database at the end, the
# lab is then as setup/install.sh left it. Run by the CI, after setup/test-lab.sh.
# Usage: ./setup/test-reseed.sh     (with Podman: ENGINE=podman ./setup/test-reseed.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
. setup/lib.sh
cleanup() {
    bash setup/ag-remove.sh AgReseed >/dev/null || true
    sql hadrlab1 -h -1 -Q "SET NOCOUNT ON; IF DB_ID(N't_reseed') IS NOT NULL DROP DATABASE t_reseed;" || true
    $engine exec hadrlab1 rm -rf /var/opt/mssql/share/t_reseed || true
}
trap cleanup EXIT
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/share/t_reseed';
CREATE DATABASE t_reseed;
ALTER DATABASE t_reseed SET RECOVERY FULL;
BACKUP DATABASE t_reseed TO DISK = N'/var/opt/mssql/share/t_reseed/t_reseed-full.bak' WITH INIT;
SQL
bash setup/ag-create.sh AgReseed t_reseed
sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; ALTER DATABASE t_reseed SET HADR OFF;"
echo "hadrlab2: t_reseed taken out of the group, $(sql hadrlab2 -h -1 -Q "SET NOCOUNT ON; SELECT state_desc FROM sys.databases WHERE name = N't_reseed'")"
out=$(wait_ag_database hadrlab1 AgReseed t_reseed 300 hadrlab2 2>&1) || { echo "$out"; echo "FAIL the copy was not seeded again"; exit 1; }
echo "$out"
if ! echo "$out" | grep -q 'seeding started again'; then
    echo "FAIL the copy was caught up without being seeded again: the test did not test the reseeding"
    exit 1
fi
echo "ok   a stopped seeding is seeded again"
