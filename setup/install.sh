#!/usr/bin/env bash
# Downloads the backup, checks it, starts the three instances, restores PachadataTraining
# on hadrlab1 (full recovery model, first full backup), creates the endpoints and exchanges
# their certificates through the shared volume, then checks the lab with setup/test-lab.sh.
# Usage: ./setup/install.sh
#   With Podman: COMPOSE="podman compose" ENGINE=podman ./setup/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."
compose=${COMPOSE:-docker compose}
engine=${ENGINE:-docker}
nodes="hadrlab1 hadrlab2 hadrlab3"
bak=PachadataTraining-2026-10.bak
mkdir -p setup/backup

fetch() {  # name, url, sha256
    local f=setup/backup/$1
    if [ ! -f "$f" ]; then
        echo "Downloading $1..."
        curl -fL --retry 3 -o "$f.part" "$2"
        mv "$f.part" "$f"
    fi
    local got
    if command -v sha256sum >/dev/null; then got=$(sha256sum "$f" | cut -d' ' -f1)
    else got=$(shasum -a 256 "$f" | cut -d' ' -f1); fi
    if [ "$got" != "$3" ]; then
        echo "Checksum mismatch for $f: delete it and run this script again." >&2
        exit 1
    fi
}
fetch $bak \
    'https://files.pachadata.com/public/api/raw?hash=tAsyC50c6kfVadBp3zc6TQ&file=/PachadataTraining/SqlServer/PachadataTraining-2026-10.bak' \
    1d05970d8e0576cd0c57bddba64c2ba8a583845ad4744adeb75d2ea4a3f7d44e

# Git Bash on Windows rewrites /var/opt/... arguments without this; no effect elsewhere.
export MSYS_NO_PATHCONV=1
sql() {  # instance, then sqlcmd arguments; the password comes from the container environment
    local c=$1; shift
    $engine exec -i $c /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U sa -C -b -I "$@"
}

$compose up -d --wait
# The shared volume is created empty and owned by root: SQL Server runs as mssql.
$engine exec -u 0 hadrlab1 mkdir -p /var/opt/mssql/share/certs /var/opt/mssql/share/logship
$engine exec -u 0 hadrlab1 chown -R mssql:mssql /var/opt/mssql/share

if [ -z "$($engine exec hadrlab1 ls /var/opt/mssql/share/$bak 2>/dev/null)" ]; then
    $engine cp setup/backup/$bak hadrlab1:/var/opt/mssql/share/$bak
    $engine exec -u 0 hadrlab1 chown mssql:mssql /var/opt/mssql/share/$bak
fi
sql hadrlab1 < setup/restore.sql

for n in $nodes; do
    $engine exec hadrlab1 rm -f /var/opt/mssql/share/certs/${n}_cert.cer
    sql $n -v N=$n < setup/endpoint.sql
done
for n in $nodes; do
    for p in $nodes; do
        [ $p = $n ] && continue
        sql $n -v P=$p < setup/peer.sql
    done
done
ENGINE=$engine ./setup/test-lab.sh
