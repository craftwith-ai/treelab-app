#!/usr/bin/env bash
# Merges upstream cmux into the current branch and keeps out the folders this fork does not ship:
# the server folders under the Business Source License (see LICENSE, which stays unchanged).
#
# Usage: scripts/treelab/merge-upstream.sh [--no-commit] [<ref>]   (default ref: upstream/main)
#
# 1. git merge --no-commit <ref> (clean tree and no merge in progress required);
# 2. every path the merge brings back under a removed folder is removed again (git rm): an
#    upstream change to a file we deleted is a modify/delete conflict, resolved here alone;
# 3. a conflict left anywhere else stops the script: exit code 1, merge left in place for a
#    person to resolve (git merge --abort undoes it);
# 4. otherwise the merge is committed (or left staged with --no-commit), exit code 0.
# Prints KEY=value lines: BUSL_RESOLVED, BUSL_DROPPED, CONFLICTS, then MERGE=.
set -euo pipefail

REMOVED_PATHS=(
  web
  workers/ci-artifacts
  workers/iroh-v2
  workers/presence
  services/iroh-relay-minter
  cmux-tui/relays/cloudflare-do
)

commit=1
ref=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-commit) commit=0; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    -*) echo "error: unknown option $1" >&2; exit 2 ;;
    *) [[ -z "$ref" ]] || { echo "error: one ref at most" >&2; exit 2; }; ref="$1"; shift ;;
  esac
done
ref="${ref:-upstream/main}"

die() { echo "error: $*" >&2; exit 2; }
git rev-parse --show-toplevel >/dev/null 2>&1 || die "not inside a git repository"
cd "$(git rev-parse --show-toplevel)"
git rev-parse --verify --quiet "$ref^{commit}" >/dev/null || die "unknown ref $ref (git fetch first?)"
[[ ! -e "$(git rev-parse --git-path MERGE_HEAD)" ]] || die "a merge is already in progress"
if ! git diff --quiet || ! git diff --cached --quiet; then die "uncommitted changes: commit or set them aside first"; fi

merge_rc=0
git merge --no-ff --no-commit "$ref" >/dev/null 2>&1 || merge_rc=$?
if [[ ! -e "$(git rev-parse --git-path MERGE_HEAD)" ]]; then
  ((merge_rc == 0)) || die "git merge $ref failed (rc $merge_rc) before starting"
  echo "BUSL_RESOLVED=0"; echo "BUSL_DROPPED=0"; echo "CONFLICTS=0"; echo "MERGE=up-to-date"
  exit 0
fi

# Paths under the removed folders: unmerged ones are conflicts, staged ones are files brought back.
resolved="$(git diff --name-only --diff-filter=U -- "${REMOVED_PATHS[@]}" | sort -u)"
dropped="$(git ls-files -- "${REMOVED_PATHS[@]}" | sort -u)"
git rm -r -q -f --ignore-unmatch -- "${REMOVED_PATHS[@]}" >/dev/null
count() { if [[ -z "$1" ]]; then echo 0; else grep -c '' <<< "$1"; fi; }
echo "BUSL_RESOLVED=$(count "$resolved")"
echo "BUSL_DROPPED=$(count "$(comm -23 <(echo "$dropped") <(echo "$resolved") | sed '/^$/d')")"

remaining="$(git diff --name-only --diff-filter=U | sort -u)"
echo "CONFLICTS=$(count "$remaining")"
if [[ -n "$remaining" ]]; then
  while IFS= read -r path; do echo "CONFLICT=$path"; done <<< "$remaining"
  echo "MERGE=conflict"
  echo "Merge of $ref left in place: resolve the conflicts above, or git merge --abort." >&2
  exit 1
fi

if ((commit)); then
  git commit -q --no-edit
  echo "MERGE=committed"
else
  echo "MERGE=staged"
fi
