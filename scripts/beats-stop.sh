#!/bin/zsh
set -euo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${HOME}/.local/bin"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=beats_python.sh
source "${SCRIPT_DIR}/beats_python.sh"

CONFIG_HELPER="${SCRIPT_DIR}/beats_config.py"
DRY_RUN=0

usage() {
  cat <<'EOF'
BEATS stop — shutdown helper for Stream Deck

Usage:
  beats-stop.sh [--dry-run]

Actions:
  1. Quit YouTube.app if running
  2. Disconnect the headphones from config/beats-settings.json
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
  local target_name="$1"
  local configured_mac="$2"
  local connected_mac=""

  if [[ -n "$target_name" ]]; then
    connected_mac="$(connected_device_mac_by_name "$target_name")"
  fi
  if [[ -z "$connected_mac" && -n "$configured_mac" ]]; then
    connected_mac="$configured_mac"
  fi

  if [[ -z "$connected_mac" ]]; then
    log "${target_name:-headphones} not connected"
    return 0
  fi

  if (( DRY_RUN )); then
    log "[dry-run] disconnect ${target_name:-headphones} (${connected_mac})"
    return 0
  fi

  blueutil --disconnect "$connected_mac" >/dev/null
  log "Disconnected ${target_name:-headphones} (${connected_mac})"
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

target_headphones_name="$(get_setting default_headphones_name)"
target_headphones_mac="$(get_setting default_headphones_mac)"
if [[ "$target_headphones_name" == "Your Beats Name" ]]; then
  target_headphones_name=""
fi
if [[ "$target_headphones_mac" == "00:00:00:00:00:00" ]]; then
  target_headphones_mac=""
fi

boom_app_path="$(get_setting boom_3d_app)"
if [[ -z "$boom_app_path" ]]; then
  boom_app_path="/Applications/Boom 3D.app"
fi
boom_app_name="$(basename "$boom_app_path" .app)"

quit_app_if_running "YouTube"
disconnect_target_headphones "$target_headphones_name" "$target_headphones_mac"
quit_app_if_running "$boom_app_name"

log "Done"
