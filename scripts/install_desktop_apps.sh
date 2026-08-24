#!/bin/zsh
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${REPO_ROOT}/dist"
DESKTOP_DIR="${HOME}/Desktop"
BIN_DIR="${HOME}/.local/bin"

"${SCRIPT_DIR}/build_desktop_apps.sh"

for app_name in Focus_Beats Stop_Beats Beats_Source Beats_Settings Beats_Status; do
  rm -rf "${DESKTOP_DIR}/${app_name}.app"
  cp -R "${DIST_DIR}/${app_name}.app" "${DESKTOP_DIR}/"
done

mkdir -p "${BIN_DIR}"
ln -sfn "${SCRIPT_DIR}/beats" "${BIN_DIR}/beats"

printf 'Installed to %s:\n' "${DESKTOP_DIR}"
printf '  Focus_Beats.app\n  Stop_Beats.app\n  Beats_Source.app\n  Beats_Settings.app\n  Beats_Status.app\n'
printf 'Linked CLI: %s -> %s\n' "${BIN_DIR}/beats" "${SCRIPT_DIR}/beats"
if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
  printf 'Add to your shell profile if needed:\n  export PATH="%s:$PATH"\n' "${BIN_DIR}"
fi
printf 'Shortcuts should call:\n  beats lock-in "$1"\n  beats auto\n'
printf 'Stream Deck can open:\n  %s\n  %s\n' "${DIST_DIR}/Stop_Beats.app" "${SCRIPT_DIR}/beats-stop.sh"
