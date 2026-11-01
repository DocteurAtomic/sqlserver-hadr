#!/usr/bin/env bash
# ci: skip (it stops the lab; the continuous integration runs setup/stop.sh in its own step)
# Clip 1.3: pause the lab and start it again. setup/stop.sh shuts each instance down, then
# compose starts the three containers, and setup/test-lab.sh checks them once the Agent is
# up (a few seconds after the instance answers). The error log of hadrlab1 shows a clean
# stop: no transaction to roll forward at the start.
# Usage: ./demos/module_01/05-stop-start.sh   (with Podman: COMPOSE="podman compose" ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
compose=${COMPOSE:-docker compose}
t=$(date +%s.%N)
./setup/stop.sh
echo "stopped in $(awk -v s=$t -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }') s"
$engine ps -a --filter name=hadrlab --format '{{.Names}}  {{.Status}}'
t=$(date +%s.%N)
$compose up -d --wait >/dev/null 2>&1
for i in $(seq 1 30); do
    ./setup/test-lab.sh >/dev/null 2>&1 && break
    sleep 1
done
./setup/test-lab.sh | tail -1
echo "started and checked in $(awk -v s=$t -v e=$(date +%s.%N) 'BEGIN { printf "%.1f", e - s }') s"
echo
echo "hadrlab1, the end of the previous error log, then the recovery at the start:"
sql hadrlab1 -h -1 <<'SQL'
SET NOCOUNT ON;
EXEC sys.xp_readerrorlog 1, 1, N'SQL Trace was stopped due to server shutdown';
EXEC sys.xp_readerrorlog 0, 1, N'transactions rolled forward';
EXEC sys.xp_readerrorlog 0, 1, N'Recovery is complete';
SQL
