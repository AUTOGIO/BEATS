#!/bin/zsh
# Zero-input entry point for Upgrade A (Context-Aware Auto-Profile).
# See docs/PROPOSED_UPGRADES.md, upgrade A, for the full proposal.
#
# Reads live context (current Wi-Fi SSID, current time) and resolves a
# profile via `beats_config.py resolve-profile`, then hands off to
# beats-siri-trigger.sh with that profile (or blank, meaning "use the
# existing configured default" -- unchanged behavior).
#
# Meant to be triggered by something that itself has no way to prompt for
# input, e.g. a Shortcuts Automation firing on "arrive at Wi-Fi network" or
# a fixed time of day. For a manual, ask-for-profile trigger, use
# beats-siri-trigger.sh directly instead.
#
# Non-goals (see docs/PROPOSED_UPGRADES.md, upgrade A):
# - no calendar/EventKit signal in this version
# - no time ranges spanning midnight
# - no changes to beats-headphones.sh, beats-siri-trigger.sh, or the
#   existing profile/settings/source file formats

set -euo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=beats_python.sh
source "${SCRIPT_DIR}/beats_python.sh"
CONFIG_HELPER="${SCRIPT_DIR}/beats_config.py"
TRIGGER="${SCRIPT_DIR}/beats-siri-trigger.sh"

require_file() {
  if [[ ! -f "$1" ]]; then
    printf 'BEATS: missing required file %s\n' "$1" >&2
    exit 1
  fi
}

require_file "$CONFIG_HELPER"
require_file "$TRIGGER"

get_wifi_ssid() {
  "$BEATS_PYTHON" "$CONFIG_HELPER" current-wifi-ssid 2>/dev/null || true
}

WIFI_SSID="$(get_wifi_ssid || true)"
NOW="$(date +%H:%M)"

RESOLVED_PROFILE="$("$BEATS_PYTHON" "$CONFIG_HELPER" resolve-profile --wifi-ssid "$WIFI_SSID" --now "$NOW")"

exec "$TRIGGER" "$RESOLVED_PROFILE"
