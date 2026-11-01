#!/usr/bin/env bash
# Stops the lab cleanly. "docker stop" and "podman stop" kill SQL Server: the first process
# of the image does not pass SIGTERM on, so after the grace period the engine sends SIGKILL,
# and each instance recovers its databases at the next start. This script asks each
# instance for a SHUTDOWN first (checkpoint of every database, then exit), waits for its
# container to exit, and stops what would still run.
# Start the lab again with "docker compose up -d --wait" (or ./setup/install.sh), then
# check it with ./setup/test-lab.sh.
# Usage: ./setup/stop.sh     (with Podman: ENGINE=podman ./setup/stop.sh)
set -uo pipefail
cd "$(dirname "$0")/.."
. setup/lib.sh
for n in $nodes; do
    if [ "$($engine inspect -f '{{.State.Running}}' $n 2>/dev/null)" != "true" ]; then
        echo "$n: not running"; continue
    fi
    # The connection closes when the instance stops: sqlcmd may report it, it is expected.
    sql $n -Q "SHUTDOWN;" >/dev/null 2>&1
    for i in $(seq 1 60); do
        [ "$($engine inspect -f '{{.State.Running}}' $n 2>/dev/null)" = "true" ] || break
        sleep 1
    done
    if [ "$($engine inspect -f '{{.State.Running}}' $n 2>/dev/null)" = "true" ]; then
        echo "$n: still running 60 s after SHUTDOWN, stopping the container"
        $engine stop $n >/dev/null
    else
        echo "$n: SQL Server shut down, container stopped"
    fi
done
