#!/usr/bin/env bash
# Exercise of module 14, starting state: writes exercises/module_14/report.md, the answer to
# the management of PachaData to fill in (ignored by git), from the measures of your lab in
# evidence/. A report already there is kept as report.previous.md first. Lists what evidence/
# holds, file by file, with the number of measures of each. Touches neither the lab nor
# evidence/. Run it again to start over.
# Usage: ./exercises/module_14/1-start.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
f=exercises/module_14/report.md
if [ -f "$f" ]; then mv "$f" exercises/module_14/report.previous.md; echo "$f kept as exercises/module_14/report.previous.md"; fi
cat > "$f" <<'REPORT'
# Answer to the management of PachaData

<!-- Each line with a figure ends with its source, the line of evidence/ it comes from:
     [module_06.md:2] is the second line of evidence/module_06.md. Several sources may follow
     each other. Every number of the line must be in one of them, and a measure of your lab
     says its condition ("three containers on one host", or "trois conteneurs"). Write
     "not measured" where evidence/ has nothing for that solution. check.sh reads this file. -->

## Backups only
- RPO: (to fill)
- RTO: (to fill)

## Log shipping
- RPO: (to fill)
- RTO: (to fill)

## Availability group without a cluster
- RPO: (to fill)
- RTO: (to fill)
- Forced failover: (to fill)

## Windows cluster
- RPO: (to fill)
- RTO: (to fill)

## Distributed availability group
- RPO: (to fill)
- RTO: (to fill)

## What PachaData buys
- (to fill)
REPORT
echo "$f written: the report to fill in. Your measures:"
found=0
for e in evidence/module_*.md; do
    [ -f "$e" ] || continue
    found=1
    echo "  $e: $(grep -c '^- ' "$e" || true) measure(s)"
done
[ $found = 1 ] || echo "  none: evidence/ is empty (the demos of modules 1 to 14 write there)"
