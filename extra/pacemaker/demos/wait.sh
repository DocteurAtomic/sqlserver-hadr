# Sourced by the demos of extra/pacemaker: waits that print when a state is reached.
# until_true <seconds> <label> <command...>: runs the command every half second until it
# succeeds, then prints the label and the UTC time; prints a timeout otherwise.
until_true() {
    local limit=$1 label=$2; shift 2
    local end=$(( $(date +%s) + limit ))
    while [ "$(date +%s)" -lt "$end" ]; do
        if "$@" >/dev/null 2>&1; then echo "  $label at $(date -u +%T.%3N) UTC"; return 0; fi
        sleep 0.5
    done
    echo "  $label: not within $limit s"; return 1
}
role_is() {  # node, role: the local replica of AgPcs has this role
    [ "$(sql $1 -h -1 -l 2 -Q "SET NOCOUNT ON; SELECT role_desc FROM sys.dm_hadr_availability_replica_states WHERE is_local = 1" 2>/dev/null | tr -d ' \r')" = "$2" ]
}
copy_is() {  # node, state: its local copy of m13_registration has this synchronization state
    [ "$(sql $1 -h -1 -l 2 -Q "SET NOCOUNT ON; SELECT synchronization_state_desc FROM sys.dm_hadr_database_replica_states WHERE is_local = 1" 2>/dev/null | tr -d ' \r')" = "$2" ]
}
pcs_offline() {  # node: pcs on another node lists it OFFLINE
    PCS_NODE=$2 pcs status nodes 2>/dev/null | sed -n '/^Pacemaker Nodes/,/^Pacemaker Remote/p' | grep -q "^ Offline:.* $1\b"
}
pcs_online() {  # node: pcs on pc1 lists it online
    pcs status nodes 2>/dev/null | sed -n '/^Pacemaker Nodes/,/^Pacemaker Remote/p' | grep -q "^ Online:.* $1\b"
}
promoted_on() { [ "$(PCS_NODE=${2:-pc1} promoted)" = "$1" ]; }
vip_on() { podman exec "$1" ip -4 addr show eth0 2>/dev/null | grep -q "$vip/"; }
# Summarizes a writer.sh output: one line per run of identical answers, with its first time.
summary() {
    awk '{t=$1; $1=""; s=substr($0,2); if (s!=p) {if (p!="") printf "    %s x%d  %s\n", f, n, p; f=t; n=0; p=s} n++} END {if (p!="") printf "    %s x%d  %s\n", f, n, p}' "$1" | cut -c1-110
}
# The outage seen by the client of writer.sh: from the last row committed on the old primary to
# the first row committed on the new one, in seconds.
outage() {  # writer output, old primary, new primary
    local last first
    last=$(awk -v s="$2" '$2 == s {t = $1} $2 != s && t != "" {print t; exit}' "$1")
    first=$(awk -v s="$3" '$2 == s {print $1; exit}' "$1")
    [ -n "$last" ] && [ -n "$first" ] || { echo "  outage: not measured"; return; }
    echo "  outage seen by the client: last row on $2 at $last, first row on $3 at $first:" \
        "$(echo "$(date -u -d "$first" +%s.%N) - $(date -u -d "$last" +%s.%N)" | bc | sed 's/^\./0./' | cut -c1-5) s"
}
# Waits for the cluster to finish its pending actions (a move is refused while it settles).
settle() { podman exec pc1 crm_resource --wait --timeout=120 >/dev/null 2>&1 || true; }
