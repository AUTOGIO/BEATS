#!/bin/zsh
set -euo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${HOME}/.local/bin"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=beats_python.sh
source "${SCRIPT_DIR}/beats_python.sh"

CONFIG_HELPER="${SCRIPT_DIR}/beats_config.py"
TARGET_HEADPHONES_NAME="beats4"
YOUTUBE_APP_PATH="/Users/eduardofgiovannini/Applications/YouTube.app"
DRY_RUN=0

usage() {
  cat <<'EOF'
BEATS stop — shutdown helper for Stream Deck

Usage:
  beats-stop.sh [--dry-run]

Actions:
  1. Quit YouTube.app
  2. Disconnect only beats4
  3. Quit Boom 3D.app
EOF
}

log() {
  printf '[beats-stop] %s\n' "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '[beats-stop] Missing dependency: %s\n' "$1" >&2
    exit 1
  fi
}

run_step() {
  if (( DRY_RUN )); then
    printf '[beats-stop] [dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

get_setting() {
  "$BEATS_PYTHON" "$CONFIG_HELPER" get-setting "$1" 2>/dev/null || true
}

connected_device_mac_by_name() {
  "$BEATS_PYTHON" - "$1" <<'PY'
import json
import subprocess
import sys

target = sys.argv[1].strip().lower()
if not target:
    raise SystemExit(0)

data = json.loads(
    subprocess.check_output(
        ["system_profiler", "SPBluetoothDataType", "-json"],
        text=True,
    )
)

root = data.get("SPBluetoothDataType", [{}])[0]
for item in root.get("device_connected", []):
    for device_name, payload in item.items():
        if device_name.strip().lower() != target:
            continue
        if isinstance(payload, dict):
            address = str(payload.get("device_address", "")).strip()
            if address:
                print(address)
                raise SystemExit(0)
raise SystemExit(0)
PY
}

quit_app_if_running() {
  local app_name="$1"

  if ! pgrep -x "$app_name" >/dev/null 2>&1; then
    log "${app_name} not running"
    return 0
  fi

  if (( DRY_RUN )); then
    log "[dry-run] quit ${app_name}"
    return 0
  fi

  osascript -e "tell application \"$app_name\" to quit" >/dev/null 2>&1 || true
  sleep 1
  if pgrep -x "$app_name" >/dev/null 2>&1; then
    pkill -x "$app_name" >/dev/null 2>&1 || true
  fi
  log "Quit ${app_name}"
}

disconnect_target_headphones() {
  local connected_mac
  connected_mac="$(connected_device_mac_by_name "$TARGET_HEADPHONES_NAME")"

  if [[ -z "$connected_mac" ]]; then
    log "${TARGET_HEADPHONES_NAME} not connected"
    return 0
  fi

  if (( DRY_RUN )); then
    log "[dry-run] disconnect ${TARGET_HEADPHONES_NAME} (${connected_mac})"
    return 0
  fi

  blueutil --disconnect "$connected_mac" >/dev/null
  log "Disconnected ${TARGET_HEADPHONES_NAME} (${connected_mac})"
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    help|--help|-h)
      usage
      exit 0
      ;;
    *)
      printf '[beats-stop] Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

require_cmd "$BEATS_PYTHON"
require_cmd osascript
require_cmd blueutil
[[ -f "$CONFIG_HELPER" ]] || { printf '[beats-stop] Missing required file: %s\n' "$CONFIG_HELPER" >&2; exit 1; }

configured_headphones_name="$(get_setting default_headphones_name)"
if [[ -n "$configured_headphones_name" && "$configured_headphones_name" != "$TARGET_HEADPHONES_NAME" ]]; then
  log "Configured default headphones are ${configured_headphones_name}; shutdown still targets ${TARGET_HEADPHONES_NAME} only"
fi

boom_app_path="$(get_setting boom_3d_app)"
if [[ -z "$boom_app_path" ]]; then
  boom_app_path="/Applications/Boom 3D.app"
fi
boom_app_name="$(basename "$boom_app_path" .app)"

if [[ ! -d "$YOUTUBE_APP_PATH" ]]; then
  log "YouTube app path not found at ${YOUTUBE_APP_PATH}; will still try to quit any running YouTube process"
fi

quit_app_if_running "YouTube"
disconnect_target_headphones
quit_app_if_running "$boom_app_name"

log "Done"
