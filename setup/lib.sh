# Sourced by the scripts of setup/, demos/ and exercises/: the container engine, and sql(),
# which runs sqlcmd inside an instance's container, password taken from the container
# environment (SQLCMDPASSWORD, set by compose.yaml), never written on the command line.
# Usage, from a script:  . "$(dirname "$0")/../../setup/lib.sh"   then   sql hadrlab2 < file.sql
engine=${ENGINE:-docker}
nodes="hadrlab1 hadrlab2 hadrlab3"
# Git Bash on Windows rewrites /var/opt/... arguments without this; no effect elsewhere.
export MSYS_NO_PATHCONV=1
sql() {  # instance, then sqlcmd arguments
    local c=$1; shift
    $engine exec -i "$c" /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U sa -C -b -I -W "$@"
}
