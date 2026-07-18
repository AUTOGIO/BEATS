#!/bin/zsh
# Siri/Shortcuts entry point for BEATS.
#
# Purpose: give the Shortcuts app (and therefore Siri) a single, deterministic
# command to run instead of the interactive AppleScript picker. Shortcuts
# passes the dictated/typed profile name as $1; this script validates it,
# delegates to the existing beats-headphones.sh runner unchanged, and
# prints one line + a notification-friendly summary so a "Show Notification"
# step in Shortcuts has something concise to display.
#
# Non-goals (see docs/PROPOSED_UPGRADES.md for the larger context-aware idea):
# - no calendar/location/Wi-Fi based auto-selection
# - no changes to beats-headphones.sh or beats_config.py
# - no new config file format

set -euo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_HELPER="${SCRIPT_DIR}/beats_config.py"
RUNNER="${SCRIPT_DIR}/beats-headphones.sh"

require_file() {
  if [[ ! -f "$1" ]]; then
    printf 'BEATS: missing required file %s\n' "$1" >&2
    exit 1
  fi
}

require_file "$CONFIG_HELPER"
require_file "$RUNNER"

# Shortcuts passes the dictated/typed text as the first argument. Treat a
# blank, whitespace-only, or literal "default" input as "use the configured
# default profile" so the Siri phrase can be as loose as "Hey Siri, beats".
RAW_PROFILE="${1:-}"
PROFILE_NAME="$(printf '%s' "$RAW_PROFILE" | xargs || true)"
PROFILE_NAME_LOWER="$(printf '%s' "$PROFILE_NAME" | tr '[:upper:]' '[:lower:]')"

if [[ -z "$PROFILE_NAME" || "$PROFILE_NAME_LOWER" == "default" ]]; then
  PROFILE_NAME=""
fi

if [[ -n "$PROFILE_NAME" ]]; then
  KNOWN_PROFILES="$(python3 "$CONFIG_HELPER" list-profiles | cut -f1)"
  if ! printf '%s\n' "$KNOWN_PROFILES" | grep -Fxq -- "$PROFILE_NAME"; then
    printf 'BEATS: unknown profile "%s". Known profiles:\n%s\n' \
      "$PROFILE_NAME" "$KNOWN_PROFILES" >&2
    exit 64
  fi
fi

STATUS_FILE="$(python3 "$CONFIG_HELPER" get-setting status_file_path)"

RUN_ARGS=(--status-file "$STATUS_FILE")
if [[ -n "$PROFILE_NAME" ]]; then
  RUN_ARGS+=(--profile "$PROFILE_NAME")
fi

RUN_EXIT=0
"$RUNNER" "${RUN_ARGS[@]}" || RUN_EXIT=$?

SUMMARY="$(python3 - "$STATUS_FILE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    print("BEATS failed before status was recorded.")
    raise SystemExit(0)

data = json.loads(path.read_text())
profile_name = data.get("profile", {}).get("name") or "Manual session"
music_label = data.get("music", {}).get("label") or "Headphones Only"
status = "Ready" if data.get("success") else "BEATS failed"
failing = [
    s["label"] for s in data.get("steps", [])
    if s.get("status") == "error"
]
line = f"{status}: {profile_name} / {music_label}"
if failing:
    line += " (failed: " + ", ".join(failing) + ")"
print(line)
PY
)"

printf '%s\n' "$SUMMARY"
exit "$RUN_EXIT"
