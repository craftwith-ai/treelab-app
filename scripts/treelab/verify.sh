#!/usr/bin/env bash
# Runs upstream's fast static checks (scripts/verify-local.py) on Treelab: every check but
# config-schema, which compares the embedded cmux.json schema with web/data/cmux.schema.json,
# a file of the BUSL folders this fork does not ship (scripts/treelab/merge-upstream.sh keeps
# them out). The embedded copy, CmuxConfigSchema.generated.swift, stays as upstream generated it.
#
# Usage: scripts/treelab/verify.sh [extra verify-local.py options]
# Exits with verify-local.py's code.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXCLUDED_CHECKS=(config-schema)

cd "$ROOT"
checks=()
while IFS= read -r name; do
  skip=0
  for excluded in "${EXCLUDED_CHECKS[@]}"; do [[ "$name" == "$excluded" ]] && skip=1; done
  ((skip)) || checks+=(--only "$name")
done < <(python3 scripts/verify-local.py --list 2>/dev/null \
  | sed -nE 's/^([a-z0-9-]+): .+ \[(static_analysis|tests)\]$/\1/p')

((${#checks[@]} > 0)) || { echo "error: no check listed by scripts/verify-local.py --list" >&2; exit 1; }
echo "==> verify-local.py: $((${#checks[@]} / 2)) checks (excluded: ${EXCLUDED_CHECKS[*]})"
exec python3 scripts/verify-local.py "${checks[@]}" "$@"
