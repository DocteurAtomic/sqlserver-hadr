#!/usr/bin/env bash
# Exercise of module 14, one solution: writes exercises/module_14/report.md from the measures
# that evidence/ holds on this machine, whatever they are. For each figure, it takes the most
# recent line of the right module whose words say what the figure is (the line of
# demos/module_02/04-delay.sh for the RPO of the log shipping, that of 08-failover.sh for its
# RTO...), or else the most recent line of that module, and quotes it with its source and its
# condition. A solution whose module wrote nothing here is "not measured". The answer to the
# management, at the end, is the author's: it holds for any measures, and has no figure.
# Usage: ./exercises/module_14/solution/2-solution.sh
set -euo pipefail
cd "$(dirname "$0")/../../.."
f=exercises/module_14/report.md
pick() {  # file, then patterns: "L|text" of the latest line matching the first pattern found
    local file=evidence/$1 p hit; shift
    [ -f "$file" ] || return 0
    for p in "$@" '^- '; do
        hit=$(grep -n -- "$p" "$file" | grep -E '^[0-9]+:- ' | tail -1 || true)
        if [ -n "$hit" ]; then printf '%s|%s\n' "${hit%%:*}" "${hit#*:}"; return 0; fi
    done
}
quote() {  # label, file, patterns: one line of the report
    local label=$1 file=$2 got text; shift 2
    got=$(pick "$file" "$@")
    if [ -z "$got" ]; then echo "- $label: not measured"; return; fi
    # The measure without its date and module: the part between two semicolons that holds
    # the words looked for, with the condition of the measure, then its source.
    text=$(printf '%s' "${got#*|}" | sed -E 's/^- [0-9-]+( [0-9:]+ UTC)?,? module [0-9]+[,:] *//; s/[.]$//')
    full=$text
    for p in "$@"; do
        part=$(printf '%s\n' "$text" | tr ';' '\n' | grep -m1 -- "$p" || true)
        if [ -n "$part" ]; then text=$(printf '%s' "$part" | sed 's/^ *//'); break; fi
    done
    case $full in *"three containers on one host"*) case $text in *"three containers on one host"*) ;; *) text="$text; three containers on one host" ;; esac ;; esac
    case $full in *"Windows cluster"*) case $text in *"Windows cluster"*) ;; *) text="$text (trainer's Windows cluster)" ;; esac ;; esac
    echo "- $label: $text [$file:${got%%|*}]"
}
first() {  # label, then "file pattern" pairs: the first file that has a measure
    local label=$1 file pat; shift
    while [ $# -gt 0 ]; do
        file=$1 pat=$2; shift 2
        if [ -n "$(pick "$file" "$pat")" ]; then quote "$label" "$file" "$pat"; return; fi
    done
    echo "- $label: not measured"
}
if [ -f "$f" ]; then mv "$f" exercises/module_14/report.previous.md; fi
{
echo "# Answer to the management of PachaData"
echo
echo "## Backups only"
quote RPO module_01.md 'lost'
quote RTO module_01.md 'restore of'
echo
echo "## Log shipping"
quote RPO module_02.md 'readable on the secondary after' 'would have taken'
quote RTO module_02.md 'planned failover of'
echo
echo "## Availability group without a cluster"
first RPO module_06.md 'no committed row lost' module_06.md 'nothing lost' module_04.md 'HADR_SYNC_COMMIT' module_03.md 'SYNCHRONIZED'
first RTO module_06.md 'by setup/ag-failover.sh' module_06.md 'planned failover' module_11.md 'planned failover'
quote "Forced failover" module_06.md 'forced failover to'
echo
echo "## Windows cluster"
echo "- RPO: not in evidence/: no committed transaction lost in the failovers of the videos, the copies being synchronous (measured by the trainer, not on your machine)"
quote RTO module_07.md 'loses power: Pacha PRIMARY'
echo
echo "## Distributed availability group"
quote RPO module_14.md 'rows lost of'
quote RTO module_14.md 'a write accepted on hadrlab3'
echo
echo "## What PachaData buys"
echo "- A synchronous availability group under the Windows cluster for the registration site: no committed transaction lost on a failover, the failover automatic, the minutes of the outage of last month brought down to the seconds measured above."
echo "- Log shipping, or a distributed group in asynchronous commit, to a second site, for the loss of the whole room: the transactions of the last seconds at risk there, and a failover done by hand."
echo "- Never a forced failover without counting what it loses first: the figure above is what the lab lost."
} > "$f"
cat "$f"
