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

# Fail-safe, not fail-loud: if Wi-Fi lookup isn't available or the device
# isn't associated with a network, treat that as "no Wi-Fi signal" rather
# than aborting the whole auto-profile run.
get_wifi_ssid() {
  if ! command -v networksetup >/dev/null 2>&1; then
    return 0
  fi

  local iface output
  for iface in en0 en1; do
    if output="$(networksetup -getairportnetwork "$iface" 2>/dev/null)"; then
      case "$output" in
        "Current Wi-Fi Network: "*)
          printf '%s' "${output#Current Wi-Fi Network: }"
          return 0
          ;;
      esac
    fi
  done
}

WIFI_SSID="$(get_wifi_ssid || true)"
NOW="$(date +%H:%M)"

RESOLVED_PROFILE="$(python3 "$CONFIG_HELPER" resolve-profile --wifi-ssid "$WIFI_SSID" --now "$NOW")"

exec "$TRIGGER" "$RESOLVED_PROFILE"
