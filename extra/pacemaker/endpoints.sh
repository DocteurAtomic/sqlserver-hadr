#!/usr/bin/env bash
# Creates on each node a certificate and an endpoint authenticated by it, then gives each node
# the certificates of the two others (copied through the host: the nodes share no volume).
# pc3 runs the Express edition: its endpoint can only be ROLE = WITNESS.
# Usage: ./extra/pacemaker/endpoints.sh     (after lab.sh)
set -euo pipefail
cd "$(dirname "$0")"
. ./lib.sh
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for n in $nodes; do
    [ $n = pc3 ] && role=WITNESS || role=ALL
    sql $n -v N=$n ROLE=$role < sql/endpoint.sql >/dev/null
    podman cp $n:/var/opt/mssql/data/${n}_cert.cer "$tmp/"
done
for n in $nodes; do
    for p in $nodes; do
        [ $p = $n ] && continue
        podman cp "$tmp/${p}_cert.cer" $n:/var/opt/mssql/data/
        podman exec -u 0 $n chown mssql /var/opt/mssql/data/${p}_cert.cer
        sql $n -v P=$p < sql/peer.sql >/dev/null
    done
done
echo "endpoints ready on $nodes"
