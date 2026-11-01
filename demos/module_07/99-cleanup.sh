#!/usr/bin/env bash
# Module 7 leaves nothing on the containers. The cleanup removes the answers of the exercise
# (exercises/module_07/answers.txt); evidence/module_07.md is kept, like every evidence file.
# Usage: ./demos/module_07/99-cleanup.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
rm -f exercises/module_07/answers.txt
echo "Module 7 cleaned up: exercises/module_07/answers.txt removed, evidence kept."
