#!/bin/zsh
set -euo pipefail

USER_PATH="${PATH}"
PATH="/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${REPO_ROOT}/dist"
BIN_DIR="${HOME}/.local/bin"

"${SCRIPT_DIR}/build_desktop_apps.sh"

printf 'Apps ready under %s:\n' "${DIST_DIR}"
printf '  Focus_Beats.app\n  Stop_Beats.app\n  Beats_Source.app\n  Beats_Settings.app\n  Beats_Status.app\n'

mkdir -p "${BIN_DIR}"
ln -sfn "${SCRIPT_DIR}/beats" "${BIN_DIR}/beats"

printf 'Linked CLI: %s -> %s\n' "${BIN_DIR}/beats" "${SCRIPT_DIR}/beats"
if [[ ":${USER_PATH}:" != *":${BIN_DIR}:"* ]]; then
  printf 'Add to your shell profile if needed:\n  export PATH="%s:$PATH"\n' "${BIN_DIR}"
fi
printf 'Shortcuts should call:\n  beats lock-in "$1"\n'
printf 'Open apps from:\n  %s\n' "${DIST_DIR}"
printf 'Stream Deck can open:\n  %s\n  %s\n' "${DIST_DIR}/Stop_Beats.app" "${SCRIPT_DIR}/beats-stop.sh"
