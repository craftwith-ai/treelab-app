#!/usr/bin/env bash
# Measures what a running Treelab sends outside this Mac while nobody touches it.
#
# Usage: scripts/treelab/idle-net.sh [--minutes N] [--interval S] [--pid PID] [--allow-host NAME]... [--out DIR]
#   --minutes     measurement length (default 60)
#   --interval    nettop sampling period in seconds (default 5)
#   --pid         Treelab's main process (default: the only running .../Treelab.app/Contents/MacOS/Treelab)
#   --allow-host  connections to this host's current addresses are tolerated (repeatable)
#   --out         folder for the raw files (default: a new folder under $TMPDIR)
#
# Refuses any process that is not Treelab (sh.treelab.app), the user's cmux first of all.
# Keeps the Mac awake (caffeinate) and samples `nettop -t external` every 5 s for every process,
# then attributes each process to Treelab's process tree, read every second:
#   app    = Treelab and its helpers; shells = terminal shells and what they run (user config).
# Also reads SULastCheckTime and posthog.* of `defaults read sh.treelab.app` before and after.
# Prints KEY=value lines. Exit 0 when the app side sent 0 byte over 0 external connection and the
# defaults are unchanged; with --allow-host, when every app connection seen goes to an allowed
# address and no app process sent bytes without a connection seen. 1 otherwise, 2 on refusal.
set -euo pipefail

MINUTES=60
ROOT_PID=""
ALLOW_HOSTS=()
OUT=""
INTERVAL=5
BUNDLE_ID="sh.treelab.app"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --minutes) MINUTES="${2:?--minutes needs a value}"; shift 2 ;;
    --interval) INTERVAL="${2:?--interval needs a value}"; shift 2 ;;
    --pid) ROOT_PID="${2:?--pid needs a value}"; shift 2 ;;
    --allow-host) ALLOW_HOSTS+=("${2:?--allow-host needs a value}"); shift 2 ;;
    --out) OUT="${2:?--out needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "error: unknown option $1" >&2; exit 2 ;;
  esac
done
[[ "$MINUTES" =~ ^[0-9]+$ && "$MINUTES" -gt 0 ]] || { echo "error: --minutes must be a positive integer" >&2; exit 2; }
[[ "$INTERVAL" =~ ^[0-9]+$ && "$INTERVAL" -gt 0 ]] || { echo "error: --interval must be a positive integer" >&2; exit 2; }

refuse() { echo "REFUSED: $*" >&2; exit 2; }

# --- Guard: Treelab only -------------------------------------------------------------
if [[ -z "$ROOT_PID" ]]; then
  candidates=""
  while read -r pid path; do
    plist="${path%/Contents/MacOS/*}/Contents/Info.plist"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null)" == "$BUNDLE_ID" ]] \
      && candidates+="${candidates:+$'\n'}$pid"
  done < <(ps -axo pid=,comm= | awk '$2 ~ /\/Treelab\.app\/Contents\/MacOS\/Treelab$/ {print $1, $2}')
  [[ -n "$candidates" ]] || refuse "no running Treelab ($BUNDLE_ID)"
  [[ "$(grep -c '' <<< "$candidates")" -eq 1 ]] || refuse "several Treelab processes ($(tr '\n' ' ' <<< "$candidates")): pass --pid"
  ROOT_PID="$candidates"
fi
[[ "$ROOT_PID" =~ ^[0-9]+$ ]] || refuse "--pid must be a number"
executable="$(ps -o comm= -p "$ROOT_PID" 2>/dev/null || true)"
[[ -n "$executable" ]] || refuse "no process $ROOT_PID"
app_bundle="${executable%/Contents/MacOS/*}"
identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_bundle/Contents/Info.plist" 2>/dev/null || true)"
case "$identifier" in
  com.cmuxterm.app*) refuse "pid $ROOT_PID is the user's cmux ($identifier, $app_bundle): idle-net measures Treelab only" ;;
  "$BUNDLE_ID") ;;
  *) refuse "pid $ROOT_PID ($executable) is not Treelab: bundle identifier '${identifier:-none}', expected $BUNDLE_ID" ;;
esac

OUT="${OUT:-$(mktemp -d "${TMPDIR:-/tmp}/treelab-idle-net.XXXXXX")}"
mkdir -p "$OUT"
samples=$((MINUTES * 60 / INTERVAL))

read_defaults() {
  defaults read "$BUNDLE_ID" 2>/dev/null \
    | awk '/^    "?(SULastCheckTime|posthog\.)/ {p=1} p {print} /;$/ {p=0}' || true
}
resolve_hosts() {
  local host
  for host in "${ALLOW_HOSTS[@]+"${ALLOW_HOSTS[@]}"}"; do
    dscacheutil -q host -a name "$host" | awk -v h="$host" '/^ip(v6)?_address:/ {print h, $2}'
  done
}

echo "IDLE_NET_PID=$ROOT_PID"
echo "IDLE_NET_APP=$app_bundle"
echo "IDLE_NET_MINUTES=$MINUTES"
echo "IDLE_NET_OUT=$OUT"
echo "IDLE_NET_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
read_defaults > "$OUT/defaults-before.txt"
resolve_hosts > "$OUT/allowed-addresses.txt"

caffeinate -dims -w $$ &
nettop -n -t external -L "$((samples + 1))" -s "$INTERVAL" -d -x -J interface,state,bytes_in,bytes_out \
  > "$OUT/nettop.csv" 2> "$OUT/nettop.err" &
nettop_pid=$!
trap 'kill "$nettop_pid" 2>/dev/null || true' EXIT

# Treelab's process tree, every second, until nettop ends: "epoch pid ppid comm" per process.
: > "$OUT/tree.log"
while kill -0 "$nettop_pid" 2>/dev/null; do
  kill -0 "$ROOT_PID" 2>/dev/null || { echo "Treelab (pid $ROOT_PID) exited during the measurement" > "$OUT/root-exited.txt"; }
  now="$(date +%s)"
  ps -axo pid=,ppid=,comm= | awk -v root="$ROOT_PID" -v now="$now" '
    { pid=$1; ppid[pid]=$2; $1=""; $2=""; sub(/^  */, ""); comm[pid]=$0 }
    END {
      for (p in ppid) { q=p; for (i=0; i<64 && q!="" && q!=0; i++) { if (q==root) { print now, p, ppid[p], comm[p]; break } q=ppid[q] } }
    }' >> "$OUT/tree.log"
  sleep 1
done
wait "$nettop_pid" || true
trap - EXIT
resolve_hosts >> "$OUT/allowed-addresses.txt"
read_defaults > "$OUT/defaults-after.txt"
echo "IDLE_NET_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "$OUT" "$ROOT_PID" "${#ALLOW_HOSTS[@]}" <<'PY'
import os, re, sys
out, root, allow_mode = sys.argv[1], sys.argv[2], sys.argv[3] != "0"
SHELLS = {"login", "zsh", "-zsh", "bash", "-bash", "sh", "fish", "nu", "tmux"}

# Process tree: pid -> (ppid, comm), every pid ever seen under Treelab.
tree = {}
for line in open(os.path.join(out, "tree.log")):
    parts = line.rstrip("\n").split(" ", 3)
    if len(parts) == 4:
        tree[parts[1]] = (parts[2], parts[3])

def group(pid):
    """app or shell, by walking up to Treelab: a shell anywhere on the way makes it a shell."""
    seen = 0
    while pid in tree and pid != root and seen < 64:
        ppid, comm = tree[pid]
        if os.path.basename(comm) in SHELLS:
            return "shell"
        pid, seen = ppid, seen + 1
    return "app"

allowed = set()
for line in open(os.path.join(out, "allowed-addresses.txt")):
    parts = line.split()
    if len(parts) == 2:
        allowed.add(parts[1].lower())

proc_re = re.compile(r"^(.+)\.(\d+)$")
flow_re = re.compile(r"^(tcp|udp)[46]? (.+)<->(.+)$")
def remote_addr(remote):
    # "1.2.3.4:443", "1.2.3.4.443" or "2a06:98c1:58::da.443": strip the port
    m = re.match(r"^(.*)[.:](\d+|\*)$", remote)
    return (m.group(1) if m else remote).lower()

totals = {g: {"in": 0, "out": 0, "flows": set(), "allowed_flows": set(), "remotes": set()} for g in ("app", "shell")}
procs = {}  # "name.pid" -> [group, in, out, flows seen, allowed flows seen]
others = {}
current = None
for line in open(os.path.join(out, "nettop.csv"), errors="replace"):
    cols = line.rstrip("\n").split(",")
    if len(cols) < 5 or cols[0] in ("", "time"):
        continue
    name = cols[0]
    try:
        bin_, bout = int(cols[-3] or 0), int(cols[-2] or 0)
    except ValueError:
        continue
    m = proc_re.match(name)
    if m and not flow_re.match(name):
        pid = m.group(2)
        current = (m.group(1), pid, pid == root or pid in tree)
        if current[2]:
            g = totals[group(pid)]
            g["in"] += bin_; g["out"] += bout
            entry = procs.setdefault(name, [group(pid), 0, 0, 0, 0])
            entry[1] += bin_; entry[2] += bout
        elif bin_ or bout:
            others.setdefault(m.group(1), [0, 0])
            others[m.group(1)][0] += bin_; others[m.group(1)][1] += bout
        continue
    f = flow_re.match(name)
    if f and current and current[2]:
        g = totals[group(current[1])]
        addr = remote_addr(f.group(3))
        key = f"{current[0]}.{current[1]} {name}"
        entry = procs.setdefault(f"{current[0]}.{current[1]}", [group(current[1]), 0, 0, 0, 0])
        if addr in allowed:
            g["allowed_flows"].add(key); entry[4] += 1
        else:
            g["flows"].add(key); g["remotes"].add(addr); entry[3] += 1

for gname, g in totals.items():
    prefix = gname.upper()
    print(f"{prefix}_BYTES_IN={g['in']}")
    print(f"{prefix}_BYTES_OUT={g['out']}")
    print(f"{prefix}_CONNECTIONS={len(g['flows'])}")
    print(f"{prefix}_ALLOWED_CONNECTIONS={len(g['allowed_flows'])}")
    print(f"{prefix}_REMOTES={' '.join(sorted(g['remotes']))}")
    for flow in sorted(g["flows"] | g["allowed_flows"]):
        print(f"{prefix}_CONNECTION={flow}")
for name, (gname, bin_, bout, nflows, nallowed) in sorted(procs.items()):
    print(f"{gname.upper()}_PROCESS={name} in={bin_} out={bout} connections={nflows} allowed={nallowed}")
app_pids = sorted({p for p in tree if group(p) == "app"}, key=int)
shell_pids = sorted({p for p in tree if group(p) == "shell"}, key=int)
print("APP_PIDS=" + " ".join(f"{p}:{os.path.basename(tree[p][1])}" for p in app_pids))
print("SHELL_PIDS=" + " ".join(f"{p}:{os.path.basename(tree[p][1])}" for p in shell_pids))
suspects = {"Treelab", "cmux", "gh", "git", "ssh", "curl", "login", "zsh", "bash", "sh"}
for name, (bin_, bout) in sorted(others.items()):
    if name in suspects:
        print(f"OUTSIDE_TREE_SAME_NAME={name} in={bin_} out={bout}")
before = open(os.path.join(out, "defaults-before.txt")).read()
after = open(os.path.join(out, "defaults-after.txt")).read()
print(f"DEFAULTS_UNCHANGED={'yes' if before == after else 'no'}")
app = totals["app"]
alive = not os.path.exists(os.path.join(out, "root-exited.txt"))
if allow_mode:
    # bytes from a process with no allowed connection seen have an unknown destination
    unseen = [n for n, e in procs.items() if e[0] == "app" and (e[1] or e[2]) and not e[4]]
    for name in sorted(unseen):
        print(f"APP_UNKNOWN_DESTINATION={name}")
    ok = not app["flows"] and not unseen and alive
    print(f"RESULT={'allowed-only' if ok else 'traffic'}")
else:
    ok = app["out"] == 0 and not app["flows"] and before == after and alive
    print(f"RESULT={'zero' if ok else 'traffic'}")
sys.exit(0 if ok else 1)
PY
