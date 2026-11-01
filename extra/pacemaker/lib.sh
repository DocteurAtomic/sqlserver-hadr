# Sourced by the scripts of extra/pacemaker: the names of the Pacemaker lab and sql(), which
# runs sqlcmd inside a node, password taken from the node's environment (SQLCMDPASSWORD, set
# by lab.sh), never written on the command line. Podman only: the nodes run systemd.
# Usage, from a script of extra/pacemaker:  . "$(dirname "$0")/lib.sh"   then   sql pc1 < file.sql
nodes="pc1 pc2 pc3"
net=hadr-pcs
subnet=10.89.50.0/24
vip=10.89.50.20                    # the virtual address of the listener (IPaddr2 resource)
image=hadr-pcs:2025
ag=AgPcs
db=m13_registration
# Lab passwords, written in clear: never reuse them elsewhere.
sa_password=${MSSQL_SA_PASSWORD:-Hadr-2026!lab}
hacluster_password=${HACLUSTER_PASSWORD:-Pcs-2026!lab}
pacemaker_password=${PACEMAKER_PASSWORD:-Pacemaker-2026!lab}
sql() {  # node, then sqlcmd arguments
    local c=$1; shift
    podman exec -i "$c" /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U sa -C -b -I -W "$@"
}
pcs() {  # pcs, run on pc1 unless PCS_NODE names another node
    podman exec -i "${PCS_NODE:-pc1}" pcs "$@"
}
# The node that holds the promoted (primary) instance of the AG resource, read in pcs status.
promoted() {
    # pcs 0.11 prints "ag_cluster (ocf:mssql:ag): Promoted pc1"; older ones "Masters: [ pc1 ]".
    pcs status resources 2>/dev/null | sed -n -e 's/.*ocf:mssql:ag.*Promoted \([a-z0-9]*\).*/\1/p' \
        -e 's/.*\(Promoted\|Masters\): *\[ *\([a-z0-9]*\).*/\2/p' | head -1
}
# Opens one connection to a server from inside the lab network (the sqlcmd of a node) and prints
# where it landed: the instance and the database, or the error the connection got.
# Usage:  lands_on <from node> <server> [sqlcmd options]     e.g.  lands_on pc3 10.89.50.20 -d m13_registration
lands_on() {
    local from=$1 server=$2; shift 2
    podman exec -i "$from" /opt/mssql-tools18/bin/sqlcmd -C -l 3 -S "$server" -U sa -h -1 -W "$@" \
        -Q "SET NOCOUNT ON; SELECT CONCAT(@@SERVERNAME, N' ', DB_NAME())" 2>&1 \
        | grep -v '^ *$' | tail -1 | sed 's/^Sqlcmd: Error: Microsoft ODBC Driver 18 for SQL Server : //'
    return 0
}
