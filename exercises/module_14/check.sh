#!/usr/bin/env bash
# Exercise of module 14: checks exercises/module_14/report.md, the answer to the management of
# PachaData, against your measures in evidence/. It reads the two, never the corrected version:
#   - the six sections of 1-start.sh are there, the five solutions with an RPO line and an RTO
#     line, and no "(to fill)" is left;
#   - a line with a figure names its source, [module_NN.md:L], the line L of evidence/module_NN.md,
#     and that line exists;
#   - every number of the line is in one of its sources (1,000, 1 000 and 1000 are the same
#     number, so are 4.6 and 4,6; a 0 also matches a source that says "no" or "nothing");
#   - a line whose source was measured on three containers on one host says so ("three
#     containers" or "trois conteneurs"), and one whose source is the Windows cluster says
#     "Windows cluster" or "cluster Windows";
#   - a solution's figures come from the modules that measured it (log shipping: module 2, the
#     distributed group: module 14...), and a solution whose evidence file has measures cites
#     at least one of them: "not measured" is right only where evidence/ has nothing.
# Numbers inside names (hadrlab1, AgSite2, m14_registration, SQL01, CU9) are not figures.
# Exits with 0 when everything holds, with 1 otherwise, saying what is wrong.
# Usage: ./exercises/module_14/check.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
report=exercises/module_14/report.md
fail=0
bad() { echo "FAIL $*"; fail=1; }
if [ ! -f "$report" ]; then
    echo "FAIL $report is missing: run exercises/module_14/1-start.sh"; exit 1
fi
sections=("Backups only" "Log shipping" "Availability group without a cluster" "Windows cluster"
          "Distributed availability group" "What PachaData buys")
allowed() {  # the evidence files of a section
    case $1 in
        "Backups only") echo "module_01.md" ;;
        "Log shipping") echo "module_02.md" ;;
        "Availability group without a cluster") echo "module_03.md module_04.md module_05.md module_06.md module_10.md module_11.md module_12.md" ;;
        "Windows cluster") echo "module_07.md module_08.md module_09.md" ;;
        "Distributed availability group") echo "module_14.md" ;;
        *) echo "*" ;;
    esac
}
nbsp=$(printf '\302\240') nnbsp=$(printf '\342\200\257')
plain() {  # a text without the names that hold digits, no-break spaces made spaces
    sed -e "s/$nnbsp/ /g" -e "s/$nbsp/ /g" -e 's/\[module_[0-9]*\.md:[0-9]*\]//g' \
        -e 's/[A-Za-z_][A-Za-z_]*[0-9][A-Za-z0-9_]*\(\.md\)\{0,1\}//g'
}
canon() {  # one number per line, written the same way: no leading zero, no trailing zero
    sed -E -e 's/^0+([0-9])/\1/' -e '/\./{s/0+$//;s/\.$//}'
}
candidates() {  # the readings of each number token of a text, one per line
    local t
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        printf '%s\n' "$t" | tr -d ' ,'                       # 1,000.5 or 1 000
        printf '%s\n' "$t" | tr -d ' .' | tr ',' '.'          # 1.000,5
        printf '%s\n' "$t" | tr -d ' ' | tr ',' '.'           # 4,6 or 1 000,5
    done < <(grep -oE '[0-9]+([ ,.][0-9]+)*') | grep -E '^[0-9]+(\.[0-9]+)?$' | canon | sort -u
}
evidence_numbers() {  # every number an evidence line can be read to say
    { printf '%s\n' "$1" | plain | candidates
      printf '%s\n' "$1" | plain | grep -oE '[0-9]+([.,][0-9]+)?' | tr ',' '.' | canon
      printf '%s\n' "$1" | plain | grep -oE '[0-9]+' | canon; } | sort -u
}
# Bash 3 (macOS) has no associative arrays: the marks are lines of one string.
marks=""
mark() { marks="$marks"$'\n'"$1"; }
marked() { printf '%s\n' "$marks" | grep -qxF -- "$1"; }
section="" in_comment=0 nline=0
while IFS= read -r line || [ -n "$line" ]; do
    nline=$((nline + 1))
    case $line in *"<!--"*) in_comment=1 ;; esac
    if [ $in_comment = 1 ]; then case $line in *"-->"*) in_comment=0 ;; esac; continue; fi
    case $line in
        "## "*) section=${line#\#\# }; section=${section%"${section##*[![:space:]]}"}; mark "section|$section"; continue ;;
        "#"*|"") continue ;;
    esac
    where="line $nline ($section)"
    mark "line|$section"
    case $line in *[Rr][Pp][Oo]*) mark "$section|RPO" ;; esac
    case $line in *[Rr][Tt][Oo]*) mark "$section|RTO" ;; esac
    case $line in *"(to fill)"*) bad "$where: still to fill"; mark "tofill|$section"; continue ;; esac
    sources=$(printf '%s\n' "$line" | grep -oE '\[module_[0-9]+\.md:[0-9]+\]' | tr -d '[]' || true)
    mine=$(printf '%s\n' "$line" | plain | candidates)
    if [ -z "$sources" ]; then
        [ -z "$mine" ] || bad "$where: a figure without its source ([module_NN.md:L]): $line"
        continue
    fi
    union="" ok_files=1
    for s in $sources; do
        file=${s%%:*} l=${s##*:}
        e=$(sed -n "${l}p" "evidence/$file" 2>/dev/null)
        case $e in
            "- "*) union="$union"$'\n'"$e" ;;
            *) bad "$where: [$s] is not a measure (evidence/$file has no line $l starting with '- ')"; ok_files=0; continue ;;
        esac
        a=$(allowed "$section")
        if [ "$a" != "*" ] && ! printf ' %s ' "$a" | grep -q " $file "; then
            bad "$where: [$s] is not a measure of this solution (expected one of: $a)"; ok_files=0
        fi
    done
    [ $ok_files = 1 ] || continue
    nums=$(evidence_numbers "$union")
    zero_ok=$(printf '%s' "$union" | grep -qiwE 'no|nothing|none' && echo 1 || echo 0)
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        hit=0
        for c in $(printf '%s\n' "$t" | candidates); do
            if printf '%s\n' "$nums" | grep -qx -- "$c" || { [ "$c" = 0 ] && [ $zero_ok = 1 ]; }; then hit=1; break; fi
        done
        [ $hit = 1 ] || bad "$where: '$t' is not in its source ($(echo $sources))"
    done < <(printf '%s\n' "$line" | plain | grep -oE '[0-9]+([ ,.][0-9]+)*')
    if printf '%s' "$union" | grep -q 'three containers on one host' \
       && ! printf '%s' "$line" | grep -qiE 'three containers|trois conteneurs'; then
        bad "$where: its source was measured on three containers on one host, and the line does not say it"
    fi
    if printf '%s' "$union" | grep -q "Windows cluster" \
       && ! printf '%s' "$line" | grep -qiE 'windows cluster|cluster windows'; then
        bad "$where: its source is the Windows cluster of the course, and the line does not say it"
    fi
    for s in $sources; do mark "$section|${s%%:*}"; done
done < "$report"
for sec in "${sections[@]}"; do
    if ! marked "section|$sec"; then bad "the section '## $sec' is missing"; continue; fi
    marked "line|$sec" || bad "'## $sec' is empty"
    marked "tofill|$sec" && continue
    a=$(allowed "$sec")
    [ "$a" = "*" ] && continue
    for k in RPO RTO; do marked "$sec|$k" || bad "'## $sec' has no $k line"; done
    have="" any=0
    for file in $a; do
        n=$(grep -c '^- ' "evidence/$file" 2>/dev/null || true)
        [ "${n:-0}" -gt 0 ] || continue
        have="$have evidence/$file ($n)"
        if marked "$sec|$file"; then any=1; fi
    done
    if [ -n "$have" ] && [ $any = 0 ]; then
        bad "'## $sec' cites none of your measures, and evidence/ has some:$have"
    elif [ -n "$have" ]; then
        echo "ok   '## $sec': figures from your measures"
    else
        echo "ok   '## $sec': nothing in evidence/ for it, no figure"
    fi
done
if [ $fail -ne 0 ]; then echo "The report is not ready yet."; exit 1; fi
echo "The report holds: every figure is in evidence/, with the condition of its measure."
