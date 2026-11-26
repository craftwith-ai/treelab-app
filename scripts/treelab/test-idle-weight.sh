#!/usr/bin/env bash
# Tests scripts/treelab/idle-weight.sh:
#   A. the user's cmux (bundle com.cmuxterm.app) is refused, rc 2, named as cmux, as --reference
#      and as --treelab;
#   B. another app, a cmux debug build and a missing or malformed pid are refused, rc 2;
# and in every refusal nothing is measured and no measurement folder is created;
#   C. Treelab (sh.treelab.app) and an upstream staging build (com.cmuxterm.app.staging.*) are
#      accepted: a 3-sample measurement follows each process tree (Treelab's child is counted) and
#      prints KEY=value lines;
#   D. --summarize on synthetic samples: median and max memory, CPU used during the window (a
#      process gone or born during it counted right), median and max process count, the
#      reference + 5 % limits and the result (processes, memory or CPU over the reference = over, rc 1);
#   E. an app that quits during the measurement gives RESULT=incomplete (rc 1), an exit recorded by an
#      earlier run in the same --out folder is not carried over, and --minutes too short for
#      --interval (a single sample) is refused, rc 2.
# The processes are a tiny waiting program compiled here (macOS kills a copied system binary)
# inside throwaway .app bundles: the real cmux is never looked at.
# Usage: scripts/treelab/test-idle-weight.sh   (exit 0 = all pass)
set -euo pipefail

SCRIPT="${IDLE_WEIGHT_SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/idle-weight.sh}"   # override: red check
WORK="$(mktemp -d "${TMPDIR:-/tmp}/treelab-idle-weight-test.XXXXXX")"
PIDS=()
cleanup() {
  for pid in "${PIDS[@]+"${PIDS[@]}"}"; do
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

# a waiting program of our own; with an argument it first forks one waiting child
printf '%s\n' '#include <unistd.h>' \
  'int main(int argc, char **argv) { (void)argv; if (argc > 1 && fork() == 0) { sleep(120); return 0; } sleep(120); return 0; }' \
  | cc -x c -o "$WORK/waiter" -

failures=0
pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
expect() { local label="$1"; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }
value() { sed -n "s/^$1=//p" "$2" | head -n 1; }

# fake_app <name> <bundle id> [fork]: starts <name>.app/Contents/MacOS/<name> (the waiter), pid in FAKE_PID
fake_app() {
  local app="$WORK/$1.app"
  mkdir -p "$app/Contents/MacOS"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $2" "$app/Contents/Info.plist" >/dev/null
  cp "$WORK/waiter" "$app/Contents/MacOS/$1"
  "$app/Contents/MacOS/$1" ${3:+"$3"} >/dev/null 2>&1 &
  FAKE_PID=$!
  PIDS+=("$FAKE_PID")
}

# run_guard <label> <args…>: runs idle-weight.sh, keeps rc and stderr, checks nothing was measured
run_guard() {
  local label="$1"; shift
  local out="$WORK/out-$label"
  RC=0
  "$SCRIPT" --interval 1 --samples 2 --out "$out" "$@" >"$WORK/$label.stdout" 2>"$WORK/$label.stderr" || RC=$?
  ERR="$(cat "$WORK/$label.stderr")"
  expect "$label: rc 2" test "$RC" -eq 2
  expect "$label: no measurement folder" test ! -e "$out"
  expect "$label: nothing measured" test ! -s "$WORK/$label.stdout"
}

fake_app Treelab sh.treelab.app fork; treelab_pid="$FAKE_PID"
fake_app cmuxref "com.cmuxterm.app.staging.treelab.ref"; ref_pid="$FAKE_PID"
fake_app cmux com.cmuxterm.app; cmux_pid="$FAKE_PID"
fake_app cmuxdebug com.cmuxterm.app.debug.tag; debug_pid="$FAKE_PID"
fake_app Other dev.example.other; other_pid="$FAKE_PID"
sleep 0.5   # let Treelab's child start

# A. the user's cmux, on either side
run_guard A1 --treelab "$treelab_pid" --reference "$cmux_pid"
expect "A1: refusal names the user's cmux" grep -q "REFUSED: pid $cmux_pid is the user's cmux (com.cmuxterm.app" <<< "$ERR"
run_guard A2 --treelab "$cmux_pid" --reference "$ref_pid"
expect "A2: refusal names the user's cmux" grep -q "REFUSED: pid $cmux_pid is the user's cmux (com.cmuxterm.app" <<< "$ERR"

# B. other apps, wrong sides, no such process, malformed pid, missing side
run_guard B1 --treelab "$treelab_pid" --reference "$other_pid"
expect "B1: refusal names the bundle" grep -q "REFUSED: pid $other_pid .* bundle identifier 'dev.example.other'" <<< "$ERR"
run_guard B2 --treelab "$treelab_pid" --reference "$debug_pid"
expect "B2: a debug build is not the reference" grep -q "REFUSED: pid $debug_pid .* 'com.cmuxterm.app.debug.tag'" <<< "$ERR"
run_guard B3 --treelab "$ref_pid" --reference "$treelab_pid"
expect "B3: sides are checked" grep -q "REFUSED: pid $ref_pid .* expected sh.treelab.app" <<< "$ERR"
run_guard B4 --treelab "$treelab_pid" --reference 999999
expect "B4: refusal says no process" grep -q "REFUSED: no process 999999" <<< "$ERR"
run_guard B5 --treelab abc --reference "$ref_pid"
expect "B5: refusal says the pid must be a number" grep -q "REFUSED: --treelab must be a number" <<< "$ERR"
run_guard B6 --treelab "$treelab_pid"
expect "B6: both sides are required" grep -q "REFUSED: --treelab and --reference are both required" <<< "$ERR"

# C. a short measurement of Treelab (with a child) beside a staging build
RC=0
"$SCRIPT" --treelab "$treelab_pid" --reference "$ref_pid" --interval 1 --samples 3 --out "$WORK/measure" \
  >"$WORK/C.stdout" 2>"$WORK/C.stderr" || RC=$?
expect "C: rc 0 or 1 (a result, no refusal)" test "$RC" -le 1
expect "C: Treelab's tree holds its child" test "$(value TREELAB_PROCS_MAX "$WORK/C.stdout")" = 2
expect "C: the reference's tree holds 1 process" test "$(value REFERENCE_PROCS_MAX "$WORK/C.stdout")" = 1
expect "C: 3 samples each" test "$(value TREELAB_SAMPLES "$WORK/C.stdout")/$(value REFERENCE_SAMPLES "$WORK/C.stdout")" = 3/3
expect "C: Treelab's memory measured" awk -v m="$(value TREELAB_MEM_MEDIAN_MIB "$WORK/C.stdout")" 'BEGIN { exit !(m > 0) }'
expect "C: the reference's memory measured" awk -v m="$(value REFERENCE_MEM_MEDIAN_MIB "$WORK/C.stdout")" 'BEGIN { exit !(m > 0) }'
expect "C: samples file names the child" test "$(awk '$2 == "treelab"' "$WORK/measure/samples.tsv" | cut -f3 | sort -u | grep -c '')" = 2
expect "C: a result line" grep -Eq '^RESULT=(within|over)$' "$WORK/C.stdout"

# D. synthetic samples: epoch label pid cpu_seconds footprint_bytes comm
MIB=1048576
synthetic() {   # $1 = reference processes per sample
  {
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      0 treelab 10 1.00 $((100 * MIB)) app   0 treelab 11 0.50 $((20 * MIB)) helper \
      30 treelab 10 1.20 $((110 * MIB)) app  30 treelab 11 0.60 $((20 * MIB)) helper  30 treelab 12 0.30 $((10 * MIB)) born \
      60 treelab 10 1.50 $((100 * MIB)) app  60 treelab 12 0.40 $((10 * MIB)) born
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      0 reference 20 2.00 $((200 * MIB)) ref  30 reference 20 2.50 $((220 * MIB)) ref  60 reference 20 3.00 $((210 * MIB)) ref
    local i
    for ((i = 2; i <= $1; i++)); do
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' 0 reference "2$i" 0 0 extra 30 reference "2$i" 0 0 extra 60 reference "2$i" 0 0 extra
    done
  } > "$WORK/synthetic-$1.tsv"
}
synthetic 1
RC=0; "$SCRIPT" --summarize "$WORK/synthetic-1.tsv" > "$WORK/D1.stdout" 2>"$WORK/D1.stderr" || RC=$?
D="$WORK/D1.stdout"
expect "D1: 3 samples" test "$(value TREELAB_SAMPLES "$D")" = 3
expect "D1: median memory 120 MiB" test "$(value TREELAB_MEM_MEDIAN_MIB "$D")" = 120.0
expect "D1: max memory 140 MiB" test "$(value TREELAB_MEM_MAX_MIB "$D")" = 140.0
expect "D1: CPU during the window 1.00 s (gone and born processes)" test "$(value TREELAB_CPU_SECONDS "$D")" = 1.00
expect "D1: median 2 processes" test "$(value TREELAB_PROCS_MEDIAN "$D")" = 2
expect "D1: max 3 processes" test "$(value TREELAB_PROCS_MAX "$D")" = 3
expect "D1: reference median 210 MiB" test "$(value REFERENCE_MEM_MEDIAN_MIB "$D")" = 210.0
expect "D1: reference CPU 1.00 s" test "$(value REFERENCE_CPU_SECONDS "$D")" = 1.00
expect "D1: memory limit = reference + 5 %" test "$(value MEM_LIMIT_MIB "$D")" = 220.5
expect "D1: CPU limit = reference + 5 %" test "$(value CPU_LIMIT_SECONDS "$D")" = 1.05
expect "D1: memory within" test "$(value MEM_OK "$D")" = yes
expect "D1: CPU within" test "$(value CPU_OK "$D")" = yes
expect "D1: more processes than the reference" test "$(value PROCS_OK "$D")" = no
expect "D1: result over, rc 1" test "$(value RESULT "$D")/$RC" = over/1
synthetic 3
RC=0; "$SCRIPT" --summarize "$WORK/synthetic-3.tsv" > "$WORK/D2.stdout" 2>"$WORK/D2.stderr" || RC=$?
expect "D2: reference median 3 processes" test "$(value REFERENCE_PROCS_MEDIAN "$WORK/D2.stdout")" = 3
expect "D2: result within, rc 0" test "$(value RESULT "$WORK/D2.stdout")/$RC" = within/0
# Treelab 10 % over the reference, in memory (D3) then in CPU (D4): one process each side
over() {   # $1 = file, $2 = Treelab MiB, $3 = Treelab CPU at the end
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    0 treelab 10 0 $(($2 * MIB)) app 30 treelab 10 0.50 $(($2 * MIB)) app 60 treelab 10 "$3" $(($2 * MIB)) app \
    0 reference 20 0 $((100 * MIB)) ref 30 reference 20 0.50 $((100 * MIB)) ref 60 reference 20 1.00 $((100 * MIB)) ref > "$1"
}
over "$WORK/D3.tsv" 110 1.00
RC=0; "$SCRIPT" --summarize "$WORK/D3.tsv" > "$WORK/D3.stdout" 2>&1 || RC=$?
expect "D3: memory 10 % over the reference" test "$(value MEM_OK "$WORK/D3.stdout")/$(value CPU_OK "$WORK/D3.stdout")" = no/yes
expect "D3: result over, rc 1" test "$(value RESULT "$WORK/D3.stdout")/$RC" = over/1
over "$WORK/D4.tsv" 100 1.10
RC=0; "$SCRIPT" --summarize "$WORK/D4.tsv" > "$WORK/D4.stdout" 2>&1 || RC=$?
expect "D4: CPU 10 % over the reference" test "$(value MEM_OK "$WORK/D4.stdout")/$(value CPU_OK "$WORK/D4.stdout")" = yes/no
expect "D4: result over, rc 1" test "$(value RESULT "$WORK/D4.stdout")/$RC" = over/1

# E1. an app that quits during the measurement makes it incomplete, never "within"
fake_app TreelabE sh.treelab.app; tle_pid="$FAKE_PID"
fake_app cmuxrefE "com.cmuxterm.app.staging.treelab.ref"; refe_pid="$FAKE_PID"
RC=0
"$SCRIPT" --treelab "$tle_pid" --reference "$refe_pid" --interval 1 --samples 4 --out "$WORK/E1" \
  > "$WORK/E1.stdout" 2>&1 &
measure_pid=$!
sleep 1.5
kill "$refe_pid"; wait "$refe_pid" 2>/dev/null || true
wait "$measure_pid" || RC=$?
expect "E1: the exit is reported" grep -q "^IDLE_WEIGHT_EXITED=pid $refe_pid exited" "$WORK/E1.stdout"
expect "E1: result incomplete, rc 1" test "$(value RESULT "$WORK/E1.stdout")/$RC" = incomplete/1

# E2. an exit recorded by an earlier run in the same --out folder is not carried over
mkdir -p "$WORK/E2"; echo "pid 1 exited before sample 0" > "$WORK/E2/exited.txt"
RC=0
"$SCRIPT" --treelab "$treelab_pid" --reference "$ref_pid" --interval 1 --samples 2 --out "$WORK/E2" \
  > "$WORK/E2.stdout" 2>&1 || RC=$?
expect "E2: no earlier exit reported" test -z "$(value IDLE_WEIGHT_EXITED "$WORK/E2.stdout")"
expect "E2: a complete result" grep -Eq '^RESULT=(within|over)$' "$WORK/E2.stdout"

# E3. --minutes too short for --interval (one sample, nothing measured) is refused
run_guard_minutes() {
  RC=0
  "$SCRIPT" --treelab "$treelab_pid" --reference "$ref_pid" --minutes 1 --interval 90 --out "$WORK/E3" \
    > "$WORK/E3.stdout" 2> "$WORK/E3.stderr" || RC=$?
}
run_guard_minutes
expect "E3: rc 2" test "$RC" -eq 2
expect "E3: says the window is too short" grep -q "error: --minutes too short for --interval" "$WORK/E3.stderr"
expect "E3: no measurement folder" test ! -e "$WORK/E3"

if ((failures)); then echo "$failures failure(s)" >&2; exit 1; fi
echo "all idle-weight tests passed"
