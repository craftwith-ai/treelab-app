#!/usr/bin/env bash
# Measures the idle weight of Treelab beside upstream cmux: two process trees, sampled together.
#
# Usage: scripts/treelab/idle-weight.sh --treelab PID --reference PID [--minutes N] [--interval S]
#                                       [--samples N] [--out DIR]
#        scripts/treelab/idle-weight.sh --summarize SAMPLES_FILE
#   --treelab    Treelab's main process (bundle sh.treelab.app)
#   --reference  upstream cmux's main process, a staging build of scripts/reloads.sh
#                (bundle com.cmuxterm.app.staging.*)
#   --minutes    measurement length (default 60): minutes * 60 / interval + 1 samples
#   --interval   seconds between samples (default 30)
#   --samples    number of samples, instead of --minutes
#   --out        folder for samples.tsv (default: a new folder under $TMPDIR)
#   --summarize  prints the summary of an existing samples file, measures nothing
#
# The user's cmux (com.cmuxterm.app) and any other app are refused (rc 2) before anything is
# measured. Each sample covers both trees: the main process, its descendants and the helpers
# macOS names it responsible for (XPC services such as WebKit's), with
#   memory    = footprint (phys_footprint) summed over the tree,
#   CPU       = cumulative CPU time of each process (ps),
#   processes = processes in the tree.
# samples.tsv, one line per process and sample: epoch label pid cpu_seconds footprint_bytes comm.
# Summary, KEY=value, for TREELAB_ and REFERENCE_: SAMPLES, MEM_MEDIAN_MIB, MEM_MAX_MIB,
# CPU_SECONDS (CPU used during the window: last minus first value of each process, whole value
# for a process born during it), PROCS_MEDIAN, PROCS_MAX; then MEM_LIMIT_MIB and CPU_LIMIT_SECONDS
# (reference + 5 %), MEM_OK, CPU_OK, PROCS_OK (median count <= the reference's) and RESULT.
# Exit 0 when RESULT=within (all three ok), 1 when RESULT=over or RESULT=incomplete (an app quit
# during the run: IDLE_WEIGHT_EXITED names it, the figures cover a shortened window), 2 on refusal
# or bad usage.
set -euo pipefail

MINUTES=60
INTERVAL=30
SAMPLES=""
OUT=""
TREELAB_PID=""
REFERENCE_PID=""
SUMMARIZE=""
TOLERANCE=1.05

refuse() { echo "REFUSED: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --treelab) TREELAB_PID="${2:?--treelab needs a value}"; shift 2 ;;
    --reference) REFERENCE_PID="${2:?--reference needs a value}"; shift 2 ;;
    --minutes) MINUTES="${2:?--minutes needs a value}"; shift 2 ;;
    --interval) INTERVAL="${2:?--interval needs a value}"; shift 2 ;;
    --samples) SAMPLES="${2:?--samples needs a value}"; shift 2 ;;
    --out) OUT="${2:?--out needs a value}"; shift 2 ;;
    --summarize) SUMMARIZE="${2:?--summarize needs a file}"; shift 2 ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "error: unknown option $1" >&2; exit 2 ;;
  esac
done

# summarize <samples.tsv>: prints the summary, exits 0 within, 1 over
summarize() {
  python3 -I - "$1" "$TOLERANCE" <<'PY'
import statistics, sys
path, tolerance = sys.argv[1], float(sys.argv[2])
MIB = 1048576
data = {}  # label -> epoch -> list of (pid, cpu, footprint)
for line in open(path):
    cols = line.rstrip("\n").split("\t")
    if len(cols) < 5:
        continue
    epoch, label, pid, cpu, fp = cols[:5]
    data.setdefault(label, {}).setdefault(int(epoch), []).append((pid, float(cpu), int(fp)))

def median(values):
    return statistics.median(values) if values else 0

summary = {}
for label in ("treelab", "reference"):
    samples = data.get(label, {})
    epochs = sorted(samples)
    mem = [sum(fp for _, _, fp in samples[e]) / MIB for e in epochs]
    procs = [len(samples[e]) for e in epochs]
    first = {pid: cpu for pid, cpu, _ in samples[epochs[0]]} if epochs else {}
    last = {}
    for e in epochs:
        for pid, cpu, _ in samples[e]:
            last[pid] = cpu
    cpu_used = sum(cpu - first.get(pid, 0.0) for pid, cpu in last.items())
    summary[label] = (median(mem), max(mem, default=0), cpu_used, median(procs), max(procs, default=0))
    prefix = label.upper()
    print(f"{prefix}_SAMPLES={len(epochs)}")
    print(f"{prefix}_MEM_MEDIAN_MIB={summary[label][0]:.1f}")
    print(f"{prefix}_MEM_MAX_MIB={summary[label][1]:.1f}")
    print(f"{prefix}_CPU_SECONDS={cpu_used:.2f}")
    print(f"{prefix}_PROCS_MEDIAN={summary[label][3]:g}")
    print(f"{prefix}_PROCS_MAX={summary[label][4]}")

t, r = summary["treelab"], summary["reference"]
mem_limit, cpu_limit = r[0] * tolerance, r[2] * tolerance
# compared at the printed precision, so a printed equality never reads as over
mem_ok = round(t[0], 1) <= round(mem_limit, 1)
cpu_ok = round(t[2], 2) <= round(cpu_limit, 2)
procs_ok = t[3] <= r[3]
yes = lambda ok: "yes" if ok else "no"
print(f"MEM_LIMIT_MIB={mem_limit:.1f}")
print(f"CPU_LIMIT_SECONDS={cpu_limit:.2f}")
print(f"MEM_OK={yes(mem_ok)}")
print(f"CPU_OK={yes(cpu_ok)}")
print(f"PROCS_OK={yes(procs_ok)}")
ok = mem_ok and cpu_ok and procs_ok and bool(data.get("treelab")) and bool(data.get("reference"))
print(f"RESULT={'within' if ok else 'over'}")
sys.exit(0 if ok else 1)
PY
}

if [[ -n "$SUMMARIZE" ]]; then
  [[ -f "$SUMMARIZE" ]] || { echo "error: no samples file $SUMMARIZE" >&2; exit 2; }
  summarize "$SUMMARIZE"
  exit $?
fi

# --- Guard: Treelab and an upstream staging build only -------------------------------
[[ -n "$TREELAB_PID" && -n "$REFERENCE_PID" ]] || refuse "--treelab and --reference are both required"
[[ "$INTERVAL" =~ ^[0-9]+$ && "$INTERVAL" -gt 0 ]] || { echo "error: --interval must be a positive integer" >&2; exit 2; }
if [[ -n "$SAMPLES" ]]; then
  [[ "$SAMPLES" =~ ^[0-9]+$ && "$SAMPLES" -gt 1 ]] || { echo "error: --samples must be at least 2" >&2; exit 2; }
else
  [[ "$MINUTES" =~ ^[0-9]+$ && "$MINUTES" -gt 0 ]] || { echo "error: --minutes must be a positive integer" >&2; exit 2; }
  SAMPLES=$((MINUTES * 60 / INTERVAL + 1))
  ((SAMPLES > 1)) || { echo "error: --minutes too short for --interval (a single sample measures nothing)" >&2; exit 2; }
fi

# check_side <flag> <pid> <expected pattern> <expected text>: prints the app bundle
check_side() {
  local flag="$1" pid="$2" pattern="$3" expected="$4" executable app identifier
  [[ "$pid" =~ ^[0-9]+$ ]] || refuse "$flag must be a number"
  executable="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
  [[ -n "$executable" ]] || refuse "no process $pid"
  app="${executable%/Contents/MacOS/*}"
  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$identifier" == com.cmuxterm.app ]] \
    && refuse "pid $pid is the user's cmux ($identifier, $app): idle-weight never measures it"
  # shellcheck disable=SC2053 # $pattern is a glob on purpose
  [[ "$identifier" == $pattern ]] \
    || refuse "pid $pid ($executable) is not the $flag side: bundle identifier '${identifier:-none}', expected $expected"
  echo "$app"
}
treelab_app="$(check_side --treelab "$TREELAB_PID" sh.treelab.app sh.treelab.app)"
reference_app="$(check_side --reference "$REFERENCE_PID" 'com.cmuxterm.app.staging.?*' 'com.cmuxterm.app.staging.*')"

OUT="${OUT:-$(mktemp -d "${TMPDIR:-/tmp}/treelab-idle-weight.XXXXXX")}"
mkdir -p "$OUT"
: > "$OUT/samples.tsv"
rm -f "$OUT/exited.txt"

echo "IDLE_WEIGHT_TREELAB=$TREELAB_PID $treelab_app"
echo "IDLE_WEIGHT_REFERENCE=$REFERENCE_PID $reference_app"
echo "IDLE_WEIGHT_SAMPLES=$SAMPLES"
echo "IDLE_WEIGHT_INTERVAL=$INTERVAL"
echo "IDLE_WEIGHT_OUT=$OUT"
echo "IDLE_WEIGHT_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

caffeinate -dims -w $$ &

# sample <epoch>: one line per process of both trees, appended to samples.tsv
sample() {
  python3 -I - "$1" "$TREELAB_PID" "$REFERENCE_PID" "$OUT" <<'PY' >> "$OUT/samples.tsv"
import ctypes, json, os, re, subprocess, sys
epoch, roots, out = sys.argv[1], {"treelab": int(sys.argv[2]), "reference": int(sys.argv[3])}, sys.argv[4]
responsible = ctypes.CDLL("/usr/lib/libSystem.B.dylib").responsibility_get_pid_responsible_for_pid
responsible.argtypes, responsible.restype = [ctypes.c_int], ctypes.c_int

def seconds(text):
    # ps time: [[dd-]hh:]mm:ss.ss
    days, _, rest = text.rpartition("-")
    parts = [float(p) for p in rest.split(":")]
    value = 0.0
    for p in parts:
        value = value * 60 + p
    return value + (int(days) * 86400 if days else 0)

ppid, cpu, comm = {}, {}, {}
for row in subprocess.run(["ps", "-axo", "pid=,ppid=,time=,comm="], capture_output=True, text=True).stdout.splitlines():
    parts = row.split(None, 3)
    if len(parts) == 4:
        pid = int(parts[0])
        ppid[pid], cpu[pid], comm[pid] = int(parts[1]), seconds(parts[2]), parts[3]

tree = {}  # pid -> label
for pid in ppid:
    q = pid
    for _ in range(64):
        label = next((l for l, r in roots.items() if r == q), None)
        if label:
            tree[pid] = label
            break
        if q not in ppid or q <= 1:
            owner = responsible(pid) if pid not in roots.values() else -1
            label = next((l for l, r in roots.items() if r == owner), None)
            if label:
                tree[pid] = label
            break
        q = ppid[q]

footprint = {}
if tree:
    report = os.path.join(out, "footprint.json")
    args = ["footprint", "--noCategories", "-f", "bytes", "-j", report]
    for pid in sorted(tree):
        args += ["-p", str(pid)]
    subprocess.run(args, capture_output=True)
    try:
        for proc in json.load(open(report)).get("processes", []):
            footprint[int(proc["pid"])] = int(proc.get("footprint", 0))
    except (OSError, ValueError):
        pass
for pid, label in sorted(tree.items()):
    name = re.sub(r"\s+", " ", os.path.basename(comm[pid]))
    print(f"{epoch}\t{label}\t{pid}\t{cpu[pid]:.2f}\t{footprint.get(pid, 0)}\t{name}")
PY
}

start="$(date +%s)"
for ((i = 0; i < SAMPLES; i++)); do
  target=$((start + i * INTERVAL))
  now="$(date +%s)"
  ((target > now)) && sleep $((target - now))
  for pid in "$TREELAB_PID" "$REFERENCE_PID"; do
    kill -0 "$pid" 2>/dev/null || echo "pid $pid exited before sample $i" >> "$OUT/exited.txt"
  done
  sample "$target"
done
rm -f "$OUT/footprint.json"
echo "IDLE_WEIGHT_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ -s "$OUT/exited.txt" ]]; then
  echo "IDLE_WEIGHT_EXITED=$(head -n 1 "$OUT/exited.txt")"
fi

if [[ -s "$OUT/exited.txt" ]]; then
  # figures of a shortened window, never a verdict
  summarize "$OUT/samples.tsv" | sed 's/^RESULT=.*/RESULT=incomplete/' || true
  exit 1
fi
rc=0
summarize "$OUT/samples.tsv" || rc=$?
exit "$rc"
