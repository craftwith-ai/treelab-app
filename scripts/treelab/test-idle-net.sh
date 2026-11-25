#!/usr/bin/env bash
# Tests scripts/treelab/idle-net.sh:
#   A. a process whose bundle is com.cmuxterm.app (the user's cmux) is refused, rc 2, named as cmux;
#   B. a process of another app is refused, rc 2;
#   C. a missing or malformed --pid is refused, rc 2;
# and in every case no measurement folder is created;
#   D. a 1-minute measurement of a fake Treelab resolves an allowed host again during the run
#      (its addresses rotate), through a fake dscacheutil that answers a new address each time.
# The processes are a tiny waiting program
# compiled here (macOS kills a copied system binary) inside throwaway .app bundles: the real cmux
# is never looked at.
# Usage: scripts/treelab/test-idle-net.sh   (exit 0 = all pass)
set -euo pipefail

SCRIPT="${IDLE_NET_SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/idle-net.sh}"   # override: red check
WORK="$(mktemp -d "${TMPDIR:-/tmp}/treelab-idle-net-test.XXXXXX")"
PIDS=()
cleanup() {
  for pid in "${PIDS[@]+"${PIDS[@]}"}"; do kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done
  rm -rf "$WORK"
}
trap cleanup EXIT

# a waiting program of our own: a copy of /bin/sleep is killed by macOS launch constraints
printf '#include <unistd.h>\nint main(void) { sleep(180); return 0; }\n' | cc -x c -o "$WORK/waiter" -

failures=0
pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
expect() { local label="$1"; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }

# fake_app <name> <bundle id>: starts <name>.app/Contents/MacOS/<name> (the waiter), pid in FAKE_PID
fake_app() {
  local app="$WORK/$1.app"
  mkdir -p "$app/Contents/MacOS"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $2" "$app/Contents/Info.plist" >/dev/null
  cp "$WORK/waiter" "$app/Contents/MacOS/$1"
  "$app/Contents/MacOS/$1" >/dev/null 2>&1 &
  FAKE_PID=$!
  PIDS+=("$FAKE_PID")
}

# run_guard <label> <args…>: runs idle-net.sh, keeps rc and stderr, checks no folder was made
run_guard() {
  local label="$1"; shift
  local out="$WORK/out-$label"
  RC=0
  "$SCRIPT" --minutes 1 --out "$out" "$@" >"$WORK/$label.stdout" 2>"$WORK/$label.stderr" || RC=$?
  ERR="$(cat "$WORK/$label.stderr")"
  expect "$label: rc 2" test "$RC" -eq 2
  expect "$label: no measurement folder" test ! -e "$out"
  expect "$label: nothing measured" test ! -s "$WORK/$label.stdout"
}

# A. the user's cmux
fake_app cmux com.cmuxterm.app; cmux_pid="$FAKE_PID"
run_guard A --pid "$cmux_pid"
expect "A: refusal names the user's cmux" grep -q "REFUSED: pid $cmux_pid is the user's cmux (com.cmuxterm.app" <<< "$ERR"

# A'. a cmux variant (debug or tagged build)
fake_app cmuxdebug com.cmuxterm.app.debug.tag; debug_pid="$FAKE_PID"
run_guard A2 --pid "$debug_pid"
expect "A2: refusal names cmux" grep -q "is the user's cmux" <<< "$ERR"

# B. another app
fake_app Other dev.example.other; other_pid="$FAKE_PID"
run_guard B --pid "$other_pid"
expect "B: refusal says it is not Treelab" grep -q "is not Treelab: bundle identifier 'dev.example.other'" <<< "$ERR"

# C. no such process, malformed pid
run_guard C1 --pid 999999
expect "C1: refusal says no process" grep -q "REFUSED: no process 999999" <<< "$ERR"
run_guard C2 --pid abc
expect "C2: refusal says --pid must be a number" grep -q "REFUSED: --pid must be a number" <<< "$ERR"

# D. an allowed host is resolved again during the measurement (no network: fake resolver)
mkdir -p "$WORK/bin"
cat > "$WORK/bin/dscacheutil" <<RESOLVER
#!/bin/sh
n=\$(( \$(cat "$WORK/resolutions" 2>/dev/null || echo 0) + 1 ))
echo "\$n" > "$WORK/resolutions"
printf 'name: example.test\nip_address: 192.0.2.%s\n\n' "\$n"
RESOLVER
chmod +x "$WORK/bin/dscacheutil"
fake_app Treelab sh.treelab.app; treelab_pid="$FAKE_PID"
RC=0
PATH="$WORK/bin:$PATH" "$SCRIPT" --minutes 1 --pid "$treelab_pid" --allow-host example.test --out "$WORK/out-D" \
  >"$WORK/D.stdout" 2>"$WORK/D.stderr" || RC=$?
expect "D: measurement rc 0" test "$RC" -eq 0
distinct="$(awk '{print $2}' "$WORK/out-D/allowed-addresses.txt" 2>/dev/null | sort -u | grep -c . || true)"
expect "D: example.test resolved again during the run ($distinct addresses, at least 5)" test "${distinct:-0}" -ge 5

if ((failures > 0)); then
  echo "FAIL: $failures check(s)" >&2
  exit 1
fi
echo "PASS: idle-net.sh guard and allowed-host resolution"
