#!/usr/bin/env bash
# Runs the scripts of the course, module by module, and stops at the first error. For each
# module: the demos (demos/module_NN, except the 99- scripts), then the exercise (its
# starting scripts, exercises/module_NN/check.sh, which must exit with 1 on the starting
# state, the scripts of solution/, then check.sh again, which must exit with 0), then the
# demos' 99- scripts, which give the lab back as setup/install.sh left it.
# A .sql script names its instance in its first five lines ("-- instance: hadrlab2") and
# runs there; a .sh script runs as it is, from the root of the repository. A script whose
# first five lines contain "ci: skip" (it stops the lab, waits for the Agent, needs a
# failure provoked by hand) is not run.
# Usage: ./setup/run-scripts.sh [module_NN ...]     (with Podman: ENGINE=podman ...)
set -euo pipefail
cd "$(dirname "$0")/.."
. setup/lib.sh
export ENGINE=$engine
log=$(mktemp)
trap 'rm -f "$log"' EXIT

skipped() { head -5 "$1" | grep -q 'ci: skip'; }

run() {  # one script; prints one line, and the end of its output when it fails
    local f=$1 inst rc=0
    if skipped "$f"; then echo "skip $f"; return; fi
    case $f in
        *.sql)
            inst=$(head -5 "$f" | sed -n 's/^-- instance: *\([A-Za-z0-9_-]*\).*/\1/p' | head -1)
            if [ -z "$inst" ]; then echo "FAIL $f: no '-- instance:' line in its first five lines"; exit 1; fi
            echo "run  $f ($inst)"
            sql "$inst" < "$f" > "$log" 2>&1 || rc=$? ;;
        *.sh)
            echo "run  $f"
            bash "$f" > "$log" 2>&1 || rc=$? ;;
        *) return ;;
    esac
    if [ $rc -ne 0 ]; then echo "FAIL $f (exit $rc)"; tail -20 "$log"; exit 1; fi
}

check() {  # check.sh, and the exit code it must return
    local f=$1 want=$2 rc=0
    if skipped "$f"; then echo "skip $f"; return; fi
    bash "$f" > "$log" 2>&1 || rc=$?
    if [ $rc -ne "$want" ]; then
        echo "FAIL $f exited with $rc, expected $want"; cat "$log"; exit 1
    fi
    echo "ok   $f exits with $rc ($( [ "$want" = 0 ] && echo 'on the solution' || echo 'on the starting state'))"
}

scripts() {  # the .sql and .sh files of a folder, in name order, without check.sh
    ls "$1" 2>/dev/null | LC_ALL=C sort | grep -E '\.(sql|sh)$' | grep -v '^check\.sh$' \
        | sed "s|^|$1/|" || true
}

modules=("$@")
if [ ${#modules[@]} -eq 0 ]; then
    modules=($(ls demos exercises 2>/dev/null | grep '^module_[0-9]' | LC_ALL=C sort -u || true))
fi
for m in "${modules[@]}"; do
    for f in $(scripts demos/$m | grep -v '/99-'); do run "$f"; done
    if [ -d exercises/$m ]; then
        for f in $(scripts exercises/$m); do run "$f"; done
        [ -f exercises/$m/check.sh ] && check exercises/$m/check.sh 1
        for f in $(scripts exercises/$m/solution); do run "$f"; done
        [ -f exercises/$m/check.sh ] && check exercises/$m/check.sh 0
    fi
    for f in $(scripts demos/$m | grep '/99-'); do run "$f"; done
done
echo "All scripts ran."
