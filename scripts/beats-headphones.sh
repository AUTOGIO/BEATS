#!/bin/zsh
set -euo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_HELPER="${SCRIPT_DIR}/beats_config.py"

PROFILE_NAME=""
MUSIC_INPUT=""
STATUS_FILE=""
CLI_HEADPHONES_NAME=""
CLI_HEADPHONES_MAC=""

PROFILE_NAME_USED=""
PROFILE_DEFAULT_SOURCE_LABEL=""
PROFILE_DEFAULT_SOURCE_TYPE=""
BOOM_NOTE=""
HEADPHONES_NAME=""
HEADPHONES_MAC=""
MUSIC_LABEL=""
MUSIC_SOURCE=""
MUSIC_KIND=""
BOOM_3D_APP=""
BOOM_3D_BUNDLE_ID=""
STATUS_FILE_DEFAULT=""

STEP_PROFILE_STATUS="pending"
STEP_PROFILE_DETAIL="Waiting for profile resolution"
STEP_BOOM_STATUS="pending"
STEP_BOOM_DETAIL="Waiting to open Boom 3D"
STEP_BLUETOOTH_STATUS="pending"
STEP_BLUETOOTH_DETAIL="Waiting for Bluetooth validation"
STEP_HEADPHONES_STATUS="pending"
STEP_HEADPHONES_DETAIL="Waiting for headphone connection"
STEP_OUTPUT_STATUS="pending"
STEP_OUTPUT_DETAIL="Waiting for output routing"
STEP_INPUT_STATUS="pending"
STEP_INPUT_DETAIL="Waiting for input routing"
STEP_MUSIC_STATUS="pending"
STEP_MUSIC_DETAIL="Waiting for music startup"

log() {
  printf '[beats] %s\n' "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '[beats] Missing dependency: %s\n' "$1" >&2
    printf '[beats] Install with: brew install blueutil switchaudio-osx\n' >&2
    exit 1
  fi
}

require_file() {
  if [[ ! -f "$1" ]]; then
    printf '[beats] Missing required file: %s\n' "$1" >&2
    exit 1
  fi
}

run_with_timeout() {
  local seconds="$1"
  shift

  "$@" &
  local pid="$!"
  local elapsed=0

  while kill -0 "$pid" 2>/dev/null; do
    if (( elapsed >= seconds )); then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$pid"
}

bluetooth_state() {
  python3 - <<'PY'
import json
import subprocess

data = json.loads(subprocess.check_output(
    ["system_profiler", "SPBluetoothDataType", "-json"],
    text=True,
))["SPBluetoothDataType"][0]
print(data.get("controller_properties", {}).get("controller_state", "unknown"))
PY
}

headphones_connected() {
  python3 - "$HEADPHONES_NAME" <<'PY'
import json
import subprocess
import sys

name = sys.argv[1]
data = json.loads(subprocess.check_output(
    ["system_profiler", "SPBluetoothDataType", "-json"],
    text=True,
))["SPBluetoothDataType"][0]
for item in data.get("device_connected", []):
    if name in item:
        print("1")
        break
else:
    print("0")
PY
}

set_audio_source() {
  local source_name="$1"
  local source_type="$2"

  for attempt in {1..8}; do
    if SwitchAudioSource -a -t "$source_type" | grep -Fxq "$source_name"; then
      if SwitchAudioSource -s "$source_name" -t "$source_type" >/dev/null; then
        return 0
      fi
    fi
    sleep 1
  done

  return 1
}

prepare_boom_3d() {
  if [[ ! -d "$BOOM_3D_APP" ]]; then
    STEP_BOOM_STATUS="error"
    STEP_BOOM_DETAIL="Missing Boom 3D app at ${BOOM_3D_APP}"
    printf '[beats] %s\n' "$STEP_BOOM_DETAIL" >&2
    return 4
  fi

  log "Opening Boom 3D"
  if ! run_with_timeout 8 open -a "$BOOM_3D_APP"; then
    STEP_BOOM_STATUS="error"
    STEP_BOOM_DETAIL="Could not open Boom 3D"
    printf '[beats] %s\n' "$STEP_BOOM_DETAIL" >&2
    return 5
  fi

  for attempt in {1..10}; do
    if pgrep -f "$BOOM_3D_BUNDLE_ID" >/dev/null 2>&1 || pgrep -f "${BOOM_3D_APP}/Contents/MacOS/Boom 3D" >/dev/null 2>&1; then
      STEP_BOOM_STATUS="ok"
      if [[ -n "$BOOM_NOTE" ]]; then
        STEP_BOOM_DETAIL="Boom 3D ready; ${BOOM_NOTE}"
      else
        STEP_BOOM_DETAIL="Boom 3D ready with saved configuration"
      fi
      log "$STEP_BOOM_DETAIL"
      return 0
    fi
    sleep 1
  done

  STEP_BOOM_STATUS="error"
  STEP_BOOM_DETAIL="Boom 3D did not finish launching"
  printf '[beats] %s\n' "$STEP_BOOM_DETAIL" >&2
  return 6
}

write_status_file() {
  local exit_code="$1"
  if [[ -z "$STATUS_FILE" ]]; then
    return
  fi

  mkdir -p "$(dirname "$STATUS_FILE")"

  STATUS_FILE_PATH="$STATUS_FILE" \
  EXIT_CODE="$exit_code" \
  PROFILE_NAME_USED="$PROFILE_NAME_USED" \
  PROFILE_DEFAULT_SOURCE_LABEL="$PROFILE_DEFAULT_SOURCE_LABEL" \
  PROFILE_DEFAULT_SOURCE_TYPE="$PROFILE_DEFAULT_SOURCE_TYPE" \
  BOOM_NOTE="$BOOM_NOTE" \
  HEADPHONES_NAME="$HEADPHONES_NAME" \
  HEADPHONES_MAC="$HEADPHONES_MAC" \
  MUSIC_LABEL="$MUSIC_LABEL" \
  MUSIC_SOURCE="$MUSIC_SOURCE" \
  MUSIC_KIND="$MUSIC_KIND" \
  STEP_PROFILE_STATUS="$STEP_PROFILE_STATUS" \
  STEP_PROFILE_DETAIL="$STEP_PROFILE_DETAIL" \
  STEP_BOOM_STATUS="$STEP_BOOM_STATUS" \
  STEP_BOOM_DETAIL="$STEP_BOOM_DETAIL" \
  STEP_BLUETOOTH_STATUS="$STEP_BLUETOOTH_STATUS" \
  STEP_BLUETOOTH_DETAIL="$STEP_BLUETOOTH_DETAIL" \
  STEP_HEADPHONES_STATUS="$STEP_HEADPHONES_STATUS" \
  STEP_HEADPHONES_DETAIL="$STEP_HEADPHONES_DETAIL" \
  STEP_OUTPUT_STATUS="$STEP_OUTPUT_STATUS" \
  STEP_OUTPUT_DETAIL="$STEP_OUTPUT_DETAIL" \
  STEP_INPUT_STATUS="$STEP_INPUT_STATUS" \
  STEP_INPUT_DETAIL="$STEP_INPUT_DETAIL" \
  STEP_MUSIC_STATUS="$STEP_MUSIC_STATUS" \
  STEP_MUSIC_DETAIL="$STEP_MUSIC_DETAIL" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["STATUS_FILE_PATH"])
data = {
    "success": os.environ["EXIT_CODE"] == "0",
    "exit_code": int(os.environ["EXIT_CODE"]),
    "profile": {
        "name": os.environ["PROFILE_NAME_USED"],
        "default_source_label": os.environ["PROFILE_DEFAULT_SOURCE_LABEL"],
        "default_source_type": os.environ["PROFILE_DEFAULT_SOURCE_TYPE"],
        "boom_note": os.environ["BOOM_NOTE"],
    },
    "device": {
        "headphones_name": os.environ["HEADPHONES_NAME"],
        "headphones_mac": os.environ["HEADPHONES_MAC"],
    },
    "music": {
        "label": os.environ["MUSIC_LABEL"],
        "source": os.environ["MUSIC_SOURCE"],
        "kind": os.environ["MUSIC_KIND"],
    },
    "steps": [
        {"id": "profile", "label": "Profile", "status": os.environ["STEP_PROFILE_STATUS"], "detail": os.environ["STEP_PROFILE_DETAIL"]},
        {"id": "boom", "label": "Boom 3D", "status": os.environ["STEP_BOOM_STATUS"], "detail": os.environ["STEP_BOOM_DETAIL"]},
        {"id": "bluetooth", "label": "Bluetooth", "status": os.environ["STEP_BLUETOOTH_STATUS"], "detail": os.environ["STEP_BLUETOOTH_DETAIL"]},
        {"id": "headphones", "label": "Headphones", "status": os.environ["STEP_HEADPHONES_STATUS"], "detail": os.environ["STEP_HEADPHONES_DETAIL"]},
        {"id": "output", "label": "Output", "status": os.environ["STEP_OUTPUT_STATUS"], "detail": os.environ["STEP_OUTPUT_DETAIL"]},
        {"id": "input", "label": "Input", "status": os.environ["STEP_INPUT_STATUS"], "detail": os.environ["STEP_INPUT_DETAIL"]},
        {"id": "music", "label": "Music", "status": os.environ["STEP_MUSIC_STATUS"], "detail": os.environ["STEP_MUSIC_DETAIL"]},
    ],
}
path.write_text(json.dumps(data, indent=2) + "\n")
PY
}

parse_args() {
  if (( $# > 0 )) && [[ "$1" != --* ]]; then
    MUSIC_INPUT="$1"
    shift
  fi

  while (( $# > 0 )); do
    case "$1" in
      --profile)
        PROFILE_NAME="${2:-}"
        shift 2
        ;;
      --music-source)
        MUSIC_INPUT="${2:-}"
        shift 2
        ;;
      --status-file)
        STATUS_FILE="${2:-}"
        shift 2
        ;;
      --headphones-name)
        CLI_HEADPHONES_NAME="${2:-}"
        shift 2
        ;;
      --headphones-mac)
        CLI_HEADPHONES_MAC="${2:-}"
        shift 2
        ;;
      *)
        printf '[beats] Unknown argument: %s\n' "$1" >&2
        exit 64
        ;;
    esac
  done
}

load_runtime_context() {
  local helper_cmd=(python3 "$CONFIG_HELPER" runtime-env)
  [[ -n "$PROFILE_NAME" ]] && helper_cmd+=(--profile "$PROFILE_NAME")
  [[ -n "$MUSIC_INPUT" ]] && helper_cmd+=(--music-source "$MUSIC_INPUT")
  [[ -n "$CLI_HEADPHONES_NAME" ]] && helper_cmd+=(--headphones-name "$CLI_HEADPHONES_NAME")
  [[ -n "$CLI_HEADPHONES_MAC" ]] && helper_cmd+=(--headphones-mac "$CLI_HEADPHONES_MAC")

  eval "$("${helper_cmd[@]}")"

  if [[ -z "$STATUS_FILE" ]]; then
    STATUS_FILE="$STATUS_FILE_DEFAULT"
  fi

  if [[ -n "$PROFILE_NAME_USED" ]]; then
    STEP_PROFILE_STATUS="ok"
    STEP_PROFILE_DETAIL="Using profile ${PROFILE_NAME_USED}"
  else
    STEP_PROFILE_STATUS="ok"
    STEP_PROFILE_DETAIL="Manual session"
  fi
}

finalize() {
  local exit_code="$1"
  write_status_file "$exit_code"
}

trap 'rc=$?; finalize "$rc"' EXIT

require_cmd blueutil
require_cmd SwitchAudioSource
require_cmd osascript
require_cmd python3
require_file "$CONFIG_HELPER"

parse_args "$@"
load_runtime_context

if ! prepare_boom_3d; then
  exit $?
fi

if [[ "$(bluetooth_state)" != "attrib_on" ]]; then
  STEP_BLUETOOTH_STATUS="error"
  STEP_BLUETOOTH_DETAIL="Bluetooth is off or unavailable"
  printf '[beats] %s\n' "$STEP_BLUETOOTH_DETAIL" >&2
  exit 1
else
  STEP_BLUETOOTH_STATUS="ok"
  STEP_BLUETOOTH_DETAIL="Bluetooth already on"
  log "$STEP_BLUETOOTH_DETAIL"
fi

if [[ "$(headphones_connected)" != "1" ]]; then
  log "Connecting ${HEADPHONES_NAME}"
  run_with_timeout 15 blueutil --connect "$HEADPHONES_MAC" || true
else
  log "${HEADPHONES_NAME} already connected"
fi

for attempt in {1..10}; do
  if [[ "$(headphones_connected)" == "1" ]]; then
    break
  fi
  sleep 1
done

if [[ "$(headphones_connected)" != "1" ]]; then
  STEP_HEADPHONES_STATUS="error"
  STEP_HEADPHONES_DETAIL="Failed to connect ${HEADPHONES_NAME}"
  printf '[beats] %s\n' "$STEP_HEADPHONES_DETAIL" >&2
  exit 2
fi

STEP_HEADPHONES_STATUS="ok"
STEP_HEADPHONES_DETAIL="Connected ${HEADPHONES_NAME}"
log "$STEP_HEADPHONES_DETAIL"

log "Routing audio output to ${HEADPHONES_NAME}"
if ! set_audio_source "$HEADPHONES_NAME" output; then
  STEP_OUTPUT_STATUS="error"
  STEP_OUTPUT_DETAIL="Could not route output to ${HEADPHONES_NAME}"
  printf '[beats] %s\n' "$STEP_OUTPUT_DETAIL" >&2
  exit 3
fi
STEP_OUTPUT_STATUS="ok"
STEP_OUTPUT_DETAIL="Output routed to ${HEADPHONES_NAME}"

if SwitchAudioSource -a -t input | grep -Fxq "$HEADPHONES_NAME"; then
  log "Routing audio input to ${HEADPHONES_NAME}"
  if set_audio_source "$HEADPHONES_NAME" input; then
    STEP_INPUT_STATUS="ok"
    STEP_INPUT_DETAIL="Input routed to ${HEADPHONES_NAME}"
  else
    STEP_INPUT_STATUS="warn"
    STEP_INPUT_DETAIL="Input route skipped after retries"
  fi
else
  STEP_INPUT_STATUS="skipped"
  STEP_INPUT_DETAIL="No input target exposed for ${HEADPHONES_NAME}"
fi

if [[ -z "$MUSIC_SOURCE" || "$MUSIC_KIND" == "none" ]]; then
  STEP_MUSIC_STATUS="skipped"
  STEP_MUSIC_DETAIL="No music started"
  log "Skipping music startup"
  log "Ready"
  exit 0
fi

if [[ "$MUSIC_KIND" == "url" ]]; then
  log "Opening music source ${MUSIC_LABEL}"
  if run_with_timeout 8 open "$MUSIC_SOURCE"; then
    STEP_MUSIC_STATUS="ok"
    STEP_MUSIC_DETAIL="Opened ${MUSIC_LABEL}"
  else
    STEP_MUSIC_STATUS="warn"
    STEP_MUSIC_DETAIL="URL open timed out for ${MUSIC_LABEL}"
  fi
  log "Ready"
  exit 0
fi

log "Starting Music source ${MUSIC_LABEL}"
if run_with_timeout 8 osascript \
  -e 'tell application "Music" to activate' \
  -e "tell application \"Music\" to play playlist \"${MUSIC_SOURCE}\""; then
  STEP_MUSIC_STATUS="ok"
  STEP_MUSIC_DETAIL="Started playlist ${MUSIC_LABEL}"
else
  STEP_MUSIC_STATUS="warn"
  STEP_MUSIC_DETAIL="Music startup timed out for ${MUSIC_LABEL}"
fi

log "Ready"
