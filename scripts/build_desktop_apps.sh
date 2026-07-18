#!/bin/zsh
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${REPO_ROOT}/dist"
FOCUS_TEMPLATE="${REPO_ROOT}/src/focus_beats.applescript"
MANAGE_TEMPLATE="${REPO_ROOT}/src/beats_source.applescript"
SETTINGS_TEMPLATE="${REPO_ROOT}/src/beats_settings.applescript"
STATUS_SOURCE="${REPO_ROOT}/src/beats_status.swift"
LOCK_IN_APP="${DIST_DIR}/Focus_Beats.app"
MANAGE_APP="${DIST_DIR}/Beats_Source.app"
SETTINGS_APP="${DIST_DIR}/Beats_Settings.app"
STATUS_APP="${DIST_DIR}/Beats_Status.app"

mkdir -p "${DIST_DIR}"

compile_template() {
  local template_path="$1"
  local output_path="$2"
  local tmp_file
  local tmp_app_dir
  local tmp_app_path

  tmp_file="$(mktemp)"
  tmp_app_dir="$(mktemp -d)"
  tmp_app_path="${tmp_app_dir}/$(basename "${output_path}")"
  sed "s|__REPO_ROOT__|${REPO_ROOT}|g" "${template_path}" > "${tmp_file}"
  rm -rf "${output_path}"
  osacompile -o "${tmp_app_path}" "${tmp_file}"
  xattr -cr "${tmp_app_path}" 2>/dev/null || true
  ditto "${tmp_app_path}" "${output_path}"
  rm -f "${tmp_file}"
  rm -rf "${tmp_app_dir}"
}

compile_swift_menu_app() {
  local source_path="$1"
  local output_path="$2"
  local executable_name
  local tmp_source
  local tmp_app_dir
  local tmp_app_path
  local tmp_executable_path
  local tmp_plist_path

  executable_name="$(basename "${output_path}" .app)"
  tmp_source="$(mktemp "${TMPDIR:-/tmp}/beats_status.XXXXXX.swift")"
  tmp_app_dir="$(mktemp -d)"
  tmp_app_path="${tmp_app_dir}/${executable_name}.app"
  tmp_executable_path="${tmp_app_path}/Contents/MacOS/${executable_name}"
  tmp_plist_path="${tmp_app_path}/Contents/Info.plist"

  mkdir -p "${tmp_app_path}/Contents/MacOS" "${tmp_app_path}/Contents/Resources"
  sed "s|__REPO_ROOT__|${REPO_ROOT}|g" "${source_path}" > "${tmp_source}"
  swiftc -O -framework AppKit -framework Foundation "${tmp_source}" -o "${tmp_executable_path}"

  cat > "${tmp_plist_path}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>${executable_name}</string>
  <key>CFBundleIdentifier</key>
  <string>com.autogio.${executable_name}</string>
  <key>CFBundleName</key>
  <string>${executable_name}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

  rm -rf "${output_path}"
  xattr -cr "${tmp_app_path}" 2>/dev/null || true
  ditto "${tmp_app_path}" "${output_path}"
  rm -f "${tmp_source}"
  rm -rf "${tmp_app_dir}"
}

compile_template "${FOCUS_TEMPLATE}" "${LOCK_IN_APP}"
compile_template "${MANAGE_TEMPLATE}" "${MANAGE_APP}"
compile_template "${SETTINGS_TEMPLATE}" "${SETTINGS_APP}"
compile_swift_menu_app "${STATUS_SOURCE}" "${STATUS_APP}"

printf 'Built:\n%s\n%s\n' "${LOCK_IN_APP}" "${MANAGE_APP}"
printf '%s\n' "${SETTINGS_APP}"
printf '%s\n' "${STATUS_APP}"
