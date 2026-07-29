#!/bin/zsh
# Non-destructive environment check for BEATS.
set -euo pipefail

# Keep ~/.local/bin so a linked `beats` CLI is visible to this check.
PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=beats_python.sh
source "${SCRIPT_DIR}/beats_python.sh"

CONFIG_HELPER="${SCRIPT_DIR}/beats_config.py"
SETTINGS_PATH="${REPO_ROOT}/config/beats-settings.json"
EXAMPLE_PATH="${REPO_ROOT}/config/beats-settings.example.json"

ok=0
warn=0
fail=0

pass() {
  printf 'OK   %s\n' "$*"
  ok=$((ok + 1))
}

note() {
  printf 'WARN %s\n' "$*"
  warn=$((warn + 1))
}

bad() {
  printf 'FAIL %s\n' "$*"
  fail=$((fail + 1))
}

printf 'BEATS doctor\n'
printf 'Python: %s\n' "$BEATS_PYTHON"
"$BEATS_PYTHON" --version 2>&1 | sed 's/^/  /'

if [[ -f "$CONFIG_HELPER" ]]; then
  pass "beats_config.py present"
else
  bad "missing ${CONFIG_HELPER}"
fi

for cmd in blueutil SwitchAudioSource osascript networksetup; do
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$cmd available"
  else
    bad "$cmd missing"
  fi
done

if command -v swiftc >/dev/null 2>&1; then
  pass "swiftc available"
else
  note "swiftc missing (needed to rebuild Beats_Status.app)"
fi

if [[ -f "$SETTINGS_PATH" ]]; then
  pass "config/beats-settings.json present"
else
  bad "config/beats-settings.json missing — copy from beats-settings.example.json"
fi

if [[ -f "$EXAMPLE_PATH" ]]; then
  pass "config/beats-settings.example.json present"
fi

if [[ -f "$CONFIG_HELPER" && -f "$SETTINGS_PATH" ]]; then
  boom_path="$("$BEATS_PYTHON" "$CONFIG_HELPER" get-setting boom_3d_app 2>/dev/null || true)"
  mac="$("$BEATS_PYTHON" "$CONFIG_HELPER" get-setting default_headphones_mac 2>/dev/null || true)"
  name="$("$BEATS_PYTHON" "$CONFIG_HELPER" get-setting default_headphones_name 2>/dev/null || true)"
  status_path="$("$BEATS_PYTHON" "$CONFIG_HELPER" get-setting status_file_path 2>/dev/null || true)"

  if [[ -n "$boom_path" && -d "$boom_path" ]]; then
    pass "Boom 3D found at ${boom_path}"
  else
    bad "Boom 3D missing at ${boom_path:-<unset>}"
  fi

  if [[ "$name" == "Your Beats Name" || -z "$name" ]]; then
    note "headphones name still looks like a placeholder (${name:-empty})"
  else
    pass "headphones name: ${name}"
  fi

  if [[ "$mac" == "00:00:00:00:00:00" || -z "$mac" ]]; then
    note "headphones MAC still looks like a placeholder"
  elif [[ "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
    pass "headphones MAC format looks valid"
  else
    bad "headphones MAC format invalid: ${mac}"
  fi

  if [[ -n "$status_path" ]]; then
    status_dir="$(dirname "$status_path")"
    if mkdir -p "$status_dir" 2>/dev/null && [[ -w "$status_dir" ]]; then
      pass "status directory writable: ${status_dir}"
    else
      bad "status directory not writable: ${status_dir}"
    fi
  fi
fi

if command -v beats >/dev/null 2>&1; then
  pass "beats CLI on PATH ($(command -v beats))"
elif [[ -x "${HOME}/.local/bin/beats" ]]; then
  note "beats CLI installed at ~/.local/bin/beats but not on current PATH"
else
  note "beats CLI not installed — run ./scripts/install_desktop_apps.sh and ensure ~/.local/bin is in PATH"
fi

printf '\nSummary: %s ok, %s warn, %s fail\n' "$ok" "$warn" "$fail"
if (( fail > 0 )); then
  exit 1
fi
exit 0
