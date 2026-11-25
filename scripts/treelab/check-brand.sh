#!/usr/bin/env bash
# Checks the texts of a built Treelab.app: every "cmux" left in them (20 languages, the app and
# its nested bundles, Info.plist and InfoPlist.strings, plurals, HTML page titles, AppleScript
# dictionary) is a technical name of an allowed class (cli, gpl, commande, adresse, fichier), and
# every text file still parses (plutil -lint). Prints the count of each class.
# Rules and classes: scripts/treelab/brand-bundle.py and scripts/treelab/brand/rules.json.
#
# Usage: scripts/treelab/check-brand.sh [path/to/Treelab.app]
# Exit: 0 = every "cmux" classified, 1 = one unexplained "cmux" or an invalid file, 2 = usage error.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="${1:-$HERE/../../build/treelab/Treelab.app}"
[[ -d "$APP/Contents" ]] || { echo "error: no app bundle at $APP" >&2; exit 2; }

invalid=0
while IFS= read -r -d '' file; do
  plutil -lint -s "$file" >/dev/null 2>&1 || { echo "invalid: ${file#"$APP"/}"; invalid=$((invalid + 1)); }
done < <(find "$APP" \( -name '*.strings' -o -name '*.stringsdict' -o -name Info.plist \) -print0)
echo "INVALID_FILES=$invalid"

rc=0
python3 -I "$HERE/brand-bundle.py" check "$APP" || rc=$?
((rc == 2)) && exit 2
if ((rc != 0 || invalid != 0)); then
  echo "FAIL: $APP" >&2
  exit 1
fi
echo "PASS: $APP"
