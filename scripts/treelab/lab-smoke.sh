#!/usr/bin/env bash
# Runs lab's four gestures against a running Treelab and reads each one back:
#   1. a named tab in a workspace   (new-surface + rename-tab)      -> tree
#   2. brought to the front         (select-workspace + focus-panel) -> tree
#   3. a notification               (notify)                         -> list-notifications
#   4. a message                    (agent message + send/send-key)  -> agent inbox, read-screen
# It refuses to run when the target socket belongs to the user's cmux, and checks that
# the user's cmux tree (its window/workspace/pane/surface ids only) is the same afterwards.
#
# Usage: scripts/treelab/lab-smoke.sh [--app path/to/Treelab.app] [--socket path]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/build/treelab/Treelab.app"
SOCKET=""
STATE_DIR="$(perl -e 'print((getpwuid($<))[7])')/.local/state/treelab"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="${2:?--app needs a value}"; shift 2 ;;
    --socket) SOCKET="${2:?--socket needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "error: unknown option $1" >&2; exit 2 ;;
  esac
done

CLI="$APP/Contents/Resources/bin/cmux"
[[ -x "$CLI" ]] || { echo "error: no bundled CLI at $CLI" >&2; exit 1; }
if [[ -z "$SOCKET" ]]; then
  SOCKET="$(head -1 "$STATE_DIR/last-socket-path" 2>/dev/null || echo "$STATE_DIR/treelab.sock")"
fi

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

# --- Guard: never aim at the user's cmux -----------------------------------------
case "$SOCKET" in
  */.local/state/cmux/*|/tmp/cmux*|/private/tmp/cmux*|*"/Application Support/cmux/"*)
    fail "refusing: $SOCKET is a cmux socket path" ;;
esac
[[ -S "$SOCKET" ]] || fail "no Treelab socket at $SOCKET (is Treelab running?)"
for pid in $(lsof -t "$SOCKET" 2>/dev/null); do
  command="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
  case "$command" in
    */Treelab.app/Contents/MacOS/Treelab) ;;
    *) fail "refusing: $SOCKET is held by '$command' (pid $pid), not Treelab" ;;
  esac
done
ok "target socket $SOCKET belongs to Treelab"

# Treelab CLI in a scrubbed environment: no CMUX_WORKSPACE_ID/CMUX_SURFACE_ID or any
# other variable inherited from the user's cmux, only the explicit Treelab socket.
tl() {
  env -i HOME="$HOME" USER="${USER:-$(id -un)}" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="${TMPDIR:-/tmp}" LANG="${LANG:-en_US.UTF-8}" \
    CMUX_SOCKET_PATH="$SOCKET" "$CLI" "$@"
}

# The user's cmux, read only, through its own ambient environment: ids, never titles.
user_cmux_fingerprint() {
  command -v cmux >/dev/null 2>&1 || { echo "no-cmux-cli"; return; }
  cmux tree --all 2>/dev/null | grep -oE '(window|workspace|pane|surface):[0-9A-Za-z-]+' | sort | shasum -a 256 | cut -c1-16
}
USER_CMUX_BEFORE="$(user_cmux_fingerprint)"

[[ "$(tl ping)" == "PONG" ]] || fail "Treelab does not answer ping"
ok "ping -> PONG"

STAMP="$(date +%s)-$$"
TAB_TITLE="lab-smoke-$STAMP"

# --- 1. Named tab in a workspace ------------------------------------------------------
WORKSPACE="$(tl list-workspaces | grep -oE 'workspace:[0-9]+' | head -1)"
[[ -n "$WORKSPACE" ]] || fail "no workspace in Treelab"
created="$(tl new-surface --type terminal --workspace "$WORKSPACE" --focus false)"
SURFACE="$(grep -oE 'surface:[0-9]+' <<< "$created" | head -1)"
[[ -n "$SURFACE" ]] || fail "new-surface returned no surface: $created"
tl rename-tab --workspace "$WORKSPACE" --surface "$SURFACE" "$TAB_TITLE" >/dev/null
tl tree --workspace "$WORKSPACE" | grep -F "$SURFACE" | grep -qF "\"$TAB_TITLE\"" \
  || fail "tree does not show $SURFACE named $TAB_TITLE"
ok "1. tab $SURFACE named \"$TAB_TITLE\" in $WORKSPACE (tree)"

# --- 2. Bring it to the front ----------------------------------------------------------
tl select-workspace --workspace "$WORKSPACE" >/dev/null
tl focus-panel --panel "$SURFACE" --workspace "$WORKSPACE" >/dev/null
tree_after_focus="$(tl tree)"
grep -E "workspace $WORKSPACE " <<< "$tree_after_focus" | grep -q '\[selected\]' \
  || fail "tree does not show $WORKSPACE selected"
grep -F "surface $SURFACE " <<< "$tree_after_focus" | grep -q '\[selected\]' \
  || fail "tree does not show $SURFACE selected"
ok "2. $WORKSPACE and $SURFACE selected (tree)"

# --- 3. Notification -------------------------------------------------------------------
NOTE_BODY="lab-smoke notification $STAMP"
tl notify --title "lab-smoke" --body "$NOTE_BODY" --workspace "$WORKSPACE" --surface "$SURFACE" >/dev/null
tl list-notifications | grep -qF "$NOTE_BODY" || fail "list-notifications does not show the notification"
ok "3. notification listed (list-notifications)"

# --- 4. Message ------------------------------------------------------------------------
MESSAGE="lab-smoke message $STAMP"
tl agent message "$SURFACE" --from lab-smoke "$MESSAGE" >/dev/null
tl agent inbox --surface "$SURFACE" | grep -qF "$MESSAGE" || fail "agent inbox does not show the message"
MARK="treelab-smoke-$STAMP"
tl send --workspace "$WORKSPACE" --surface "$SURFACE" "echo $MARK-\$((6*7))" >/dev/null
tl send-key --workspace "$WORKSPACE" --surface "$SURFACE" Return >/dev/null
for _ in $(seq 1 50); do
  if tl read-screen --workspace "$WORKSPACE" --surface "$SURFACE" | grep -qx "$MARK-42"; then
    break
  fi
  sleep 0.2
done
tl read-screen --workspace "$WORKSPACE" --surface "$SURFACE" | grep -qx "$MARK-42" \
  || fail "read-screen does not show the command output $MARK-42"
ok "4. message in inbox, command ran: read-screen shows $MARK-42"

USER_CMUX_AFTER="$(user_cmux_fingerprint)"
[[ "$USER_CMUX_BEFORE" == "$USER_CMUX_AFTER" ]] \
  || fail "the user's cmux tree changed ($USER_CMUX_BEFORE -> $USER_CMUX_AFTER)"
ok "user's cmux tree ids unchanged ($USER_CMUX_AFTER)"

echo "PASS: lab gestures against Treelab ($SOCKET)"
