#!/usr/bin/env bash
# Checks that the lab is in the state that setup/install.sh leaves: the three instances
# answer, HADR and the Agent are on, each instance is bounded to 2 GB, the endpoints are
# started and know each other's certificates, PachadataTraining is on hadrlab1 in the full
# recovery model with its log chain started. Prints one line per check and exits with 1
# when one check fails or one instance does not answer.
# Usage: ./setup/test-lab.sh     (with Podman: ENGINE=podman ./setup/test-lab.sh)
set -uo pipefail
cd "$(dirname "$0")/.."
engine=${ENGINE:-docker}
export MSYS_NO_PATHCONV=1
fail=0
for n in hadrlab1 hadrlab2 hadrlab3; do
    out=$($engine exec -i $n /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U sa -C -b -I \
          -h -1 -W -v N=$n < setup/test-lab.sql 2>&1)
    if [ $? -ne 0 ] || [ -z "$out" ]; then
        echo "FAIL $n: does not answer"; echo "$out" | head -3; fail=1; continue
    fi
    echo "$out"
    echo "$out" | grep -q '^FAIL' && fail=1
done
if [ $fail -ne 0 ]; then echo "The lab is not in the expected state."; exit 1; fi
echo "The lab is ready."
