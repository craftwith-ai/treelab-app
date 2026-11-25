#!/usr/bin/env bash
# Tests scripts/treelab/merge-upstream.sh on throwaway repositories:
#   A. an upstream change in a removed folder (modify/delete) and a new file there are resolved
#      alone, the rest of the upstream change lands, the merge is committed;
#   B. a conflict outside the removed folders stops the script (rc != 0), merge left in place,
#      the removed folder already resolved;
#   C. a dirty tree is refused before any merge.
# Usage: scripts/treelab/test-merge-upstream.sh   (exit 0 = all pass)
set -euo pipefail

SCRIPT="${MERGE_UPSTREAM_SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/merge-upstream.sh}"   # override: red check
WORK="$(mktemp -d "${TMPDIR:-/tmp}/treelab-merge-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

failures=0
pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
expect() { local label="$1"; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }

# upstream: one BUSL folder (web/), one kept file, a GPL folder holding a BUSL subfolder.
new_pair() {
  local name="$1"
  git init -q -b main "$WORK/$name-upstream"
  (
    cd "$WORK/$name-upstream"
    mkdir -p web/app Sources cmux-tui/relays/cloudflare-do cmux-tui/src
    printf 'server v1\n' > web/app/page.ts
    printf 'relay v1\n' > cmux-tui/relays/cloudflare-do/index.ts
    printf 'tui v1\n' > cmux-tui/src/main.rs
    printf 'line 1\nline 2\nline 3\n' > Sources/App.swift
    printf 'license\n' > LICENSE
    git add -A && git commit -q -m "upstream base"
  )
  git clone -q "$WORK/$name-upstream" "$WORK/$name-fork"
  (
    cd "$WORK/$name-fork"
    git remote rename origin upstream
    git rm -r -q web cmux-tui/relays/cloudflare-do
    git commit -q -m "fork: drop BUSL folders"
  )
}

# A. modify/delete in web/, a new file in web/ and in the BUSL subfolder, a clean change elsewhere.
new_pair a
(
  cd "$WORK/a-upstream"
  printf 'server v2\n' > web/app/page.ts
  printf 'new route\n' > web/app/new.ts
  printf 'relay v2\n' > cmux-tui/relays/cloudflare-do/index.ts
  printf 'tui v2\n' > cmux-tui/src/main.rs
  printf 'line 1\nline 2 upstream\nline 3\n' > Sources/App.swift
  git add -A && git commit -q -m "upstream change"
)
(cd "$WORK/a-fork" && git fetch -q upstream)
rc=0; out="$(cd "$WORK/a-fork" && "$SCRIPT" upstream/main)" || rc=$?
cd "$WORK/a-fork"
expect "A: rc 0" test "$rc" -eq 0
expect "A: MERGE=committed" grep -qx 'MERGE=committed' <<< "$out"
expect "A: BUSL_RESOLVED=2 (page.ts, index.ts)" grep -qx 'BUSL_RESOLVED=2' <<< "$out"
expect "A: BUSL_DROPPED=1 (new.ts)" grep -qx 'BUSL_DROPPED=1' <<< "$out"
expect "A: no tracked file under removed folders" test -z "$(git ls-files web cmux-tui/relays/cloudflare-do)"
expect "A: removed folders absent from disk" test ! -e web -a ! -e cmux-tui/relays/cloudflare-do
expect "A: upstream change elsewhere landed" grep -q 'line 2 upstream' Sources/App.swift
expect "A: GPL sibling folder kept and merged" grep -q 'tui v2' cmux-tui/src/main.rs
expect "A: merge commit has two parents" test "$(git rev-list --parents -n 1 HEAD | wc -w)" -eq 3
expect "A: no merge left in progress" test ! -e "$(git rev-parse --git-path MERGE_HEAD)"
cd "$WORK"

# B. same line changed on both sides outside the removed folders, plus a change in web/.
new_pair b
(
  cd "$WORK/b-fork"
  printf 'line 1\nline 2 fork\nline 3\n' > Sources/App.swift
  git commit -q -am "fork change"
)
(
  cd "$WORK/b-upstream"
  printf 'line 1\nline 2 upstream\nline 3\n' > Sources/App.swift
  printf 'server v2\n' > web/app/page.ts
  git commit -q -am "upstream change"
)
(cd "$WORK/b-fork" && git fetch -q upstream)
rc=0; out="$(cd "$WORK/b-fork" && "$SCRIPT" upstream/main 2>/dev/null)" || rc=$?
cd "$WORK/b-fork"
expect "B: rc != 0" test "$rc" -ne 0
expect "B: MERGE=conflict" grep -qx 'MERGE=conflict' <<< "$out"
expect "B: CONFLICTS=1 naming Sources/App.swift" grep -qx 'CONFLICT=Sources/App.swift' <<< "$out"
expect "B: web/ conflict resolved" grep -qx 'BUSL_RESOLVED=1' <<< "$out"
expect "B: merge left in place" test -e "$(git rev-parse --git-path MERGE_HEAD)"
expect "B: no unmerged path under web/" test -z "$(git diff --name-only --diff-filter=U -- web)"
cd "$WORK"

# C. a dirty tree is refused before any merge.
new_pair c
(cd "$WORK/c-upstream" && printf 'line 1\nline 2 up\nline 3\n' > Sources/App.swift && git commit -q -am up)
(cd "$WORK/c-fork" && git fetch -q upstream && printf 'dirty\n' >> Sources/App.swift)
rc=0; (cd "$WORK/c-fork" && "$SCRIPT" upstream/main >/dev/null 2>&1) || rc=$?
cd "$WORK/c-fork"
expect "C: dirty tree refused (rc != 0)" test "$rc" -ne 0
expect "C: no merge started" test ! -e "$(git rev-parse --git-path MERGE_HEAD)"
cd "$WORK"

if ((failures > 0)); then
  echo "FAIL: $failures check(s)" >&2
  exit 1
fi
echo "PASS: merge-upstream.sh"
