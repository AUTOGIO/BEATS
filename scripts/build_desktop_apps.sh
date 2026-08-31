#!/bin/zsh
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=beats_python.sh
source "${REPO_ROOT}/scripts/beats_python.sh"

DIST_DIR="${REPO_ROOT}/dist"
FOCUS_TEMPLATE="${REPO_ROOT}/src/focus_beats.applescript"
STOP_TEMPLATE="${REPO_ROOT}/src/stop_beats.applescript"
MANAGE_TEMPLATE="${REPO_ROOT}/src/beats_source.applescript"
SETTINGS_TEMPLATE="${REPO_ROOT}/src/beats_settings.applescript"
STATUS_SOURCE="${REPO_ROOT}/src/beats_status.swift"
ICON_SOURCE="${REPO_ROOT}/assets/zR5UJ.jpg"
LOCK_IN_APP="${DIST_DIR}/Focus_Beats.app"
STOP_APP="${DIST_DIR}/Stop_Beats.app"
MANAGE_APP="${DIST_DIR}/Beats_Source.app"
SETTINGS_APP="${DIST_DIR}/Beats_Settings.app"
STATUS_APP="${DIST_DIR}/Beats_Status.app"
ICON_ICNS="${DIST_DIR}/Beats.icns"

mkdir -p "${DIST_DIR}"

substitute_template() {
  local template_path="$1"
  local output_path="$2"
  sed \
    -e "s|__REPO_ROOT__|${REPO_ROOT}|g" \
    -e "s|__BEATS_PYTHON__|${BEATS_PYTHON}|g" \
    "${template_path}" > "${output_path}"
}

build_icns() {
  local src="$1"
  local out="$2"
  local work iconset base

  if [[ ! -f "$src" ]]; then
    return 1
  fi
  if ! command -v sips >/dev/null 2>&1 || ! command -v iconutil >/dev/null 2>&1; then
    return 1
  fi

  work="$(mktemp -d)"
  iconset="${work}/App.iconset"
  base="${work}/base.png"
  mkdir -p "${iconset}"
  sips -s format png "${src}" --out "${base}" >/dev/null
  # iconutil requires this exact naming set.
  sips -z 16 16 "${base}" --out "${iconset}/icon_16x16.png" >/dev/null
  sips -z 32 32 "${base}" --out "${iconset}/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "${base}" --out "${iconset}/icon_32x32.png" >/dev/null
  sips -z 64 64 "${base}" --out "${iconset}/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "${base}" --out "${iconset}/icon_128x128.png" >/dev/null
  sips -z 256 256 "${base}" --out "${iconset}/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "${base}" --out "${iconset}/icon_256x256.png" >/dev/null
  sips -z 512 512 "${base}" --out "${iconset}/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "${base}" --out "${iconset}/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "${base}" --out "${iconset}/icon_512x512@2x.png" >/dev/null
  if ! iconutil -c icns "${iconset}" -o "${out}"; then
    rm -rf "${work}"
    return 1
  fi
  rm -rf "${work}"
}

apply_icon() {
  local app_path="$1"
  local icns_path="$2"
  local dest

  [[ -f "$icns_path" ]] || return 0
  if [[ -d "${app_path}/Contents/Resources" ]]; then
    if [[ -f "${app_path}/Contents/Resources/applet.icns" ]]; then
      dest="${app_path}/Contents/Resources/applet.icns"
    else
      dest="${app_path}/Contents/Resources/AppIcon.icns"
      /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${app_path}/Contents/Info.plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "${app_path}/Contents/Info.plist" 2>/dev/null \
        || true
    fi
    cp "${icns_path}" "${dest}"
  fi
}

compile_template() {
  local template_path="$1"
  local output_path="$2"
  local tmp_file
  local tmp_app_dir
  local tmp_app_path

  tmp_file="$(mktemp)"
  tmp_app_dir="$(mktemp -d)"
  tmp_app_path="${tmp_app_dir}/$(basename "${output_path}")"
  substitute_template "${template_path}" "${tmp_file}"
  osacompile -o "${tmp_app_path}" "${tmp_file}"
  xattr -cr "${tmp_app_path}" 2>/dev/null || true
  rm -rf "${output_path}"
  ditto "${tmp_app_path}" "${output_path}"
  apply_icon "${output_path}" "${ICON_ICNS}"
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
  substitute_template "${source_path}" "${tmp_source}"
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

  xattr -cr "${tmp_app_path}" 2>/dev/null || true
  rm -rf "${output_path}"
  ditto "${tmp_app_path}" "${output_path}"
  apply_icon "${output_path}" "${ICON_ICNS}"
  rm -f "${tmp_source}"
  rm -rf "${tmp_app_dir}"
}

if build_icns "${ICON_SOURCE}" "${ICON_ICNS}"; then
  printf 'Icon: %s\n' "${ICON_ICNS}"
else
  printf 'Icon: skipped (missing asset or sips/iconutil)\n'
fi

compile_template "${FOCUS_TEMPLATE}" "${LOCK_IN_APP}"
compile_template "${STOP_TEMPLATE}" "${STOP_APP}"
compile_template "${MANAGE_TEMPLATE}" "${MANAGE_APP}"
compile_template "${SETTINGS_TEMPLATE}" "${SETTINGS_APP}"
compile_swift_menu_app "${STATUS_SOURCE}" "${STATUS_APP}"

printf 'Built with Python %s\n' "${BEATS_PYTHON}"
printf 'Built:\n%s\n%s\n' "${LOCK_IN_APP}" "${STOP_APP}"
printf '%s\n' "${MANAGE_APP}"
printf '%s\n' "${SETTINGS_APP}"
printf '%s\n' "${STATUS_APP}"
