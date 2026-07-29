# Shared Python resolver for BEATS shell entry points.
# Prefer BEATS_PYTHON override, then /usr/bin/python3 (AppleScript parity),
# then python3 on PATH.
#
# Usage: source "${SCRIPT_DIR}/beats_python.sh"

if [[ -z "${BEATS_PYTHON:-}" ]]; then
  if [[ -x /usr/bin/python3 ]]; then
    BEATS_PYTHON="/usr/bin/python3"
  elif command -v python3 >/dev/null 2>&1; then
    BEATS_PYTHON="$(command -v python3)"
  else
    printf 'BEATS: python3 not found. Install Xcode CLT or set BEATS_PYTHON.\n' >&2
    return 1 2>/dev/null || exit 1
  fi
fi

export BEATS_PYTHON
