#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
BUILD_DIR="${PROJECT_ROOT}/build"
APP_BUNDLE="${BUILD_DIR}/Låda.app"
DMG_PATH="${BUILD_DIR}/Låda-1.5.0.dmg"
ZIP_PATH="${BUILD_DIR}/Låda-1.5.0-macOS-arm64.zip"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICNS_PATH="${PROJECT_ROOT}/Lada/Resources/AppIcon.icns"

if [[ ! -f "${ICNS_PATH}" ]]; then
  echo "==> Generating Technical Nordic macOS AppIcon.icns..."
  ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
  mkdir -p "${BUILD_DIR}"
  swift "${SCRIPT_DIR}/generate-app-icon.swift" "${ICONSET_DIR}"
  iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_PATH}"
  rm -rf "${ICONSET_DIR}"
fi

echo "==> Building Låda (Release configuration)..."
swift build -c release --package-path "${PROJECT_ROOT}"

BIN_PATH="$(swift build -c release --package-path "${PROJECT_ROOT}" --show-bin-path)/Lada"

if [[ ! -f "${BIN_PATH}" ]]; then
  echo "Error: Expected binary not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "==> Assembling macOS Application Bundle at ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/Lada"
chmod +x "${MACOS_DIR}/Lada"
cp "${PROJECT_ROOT}/Lada/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "${ICNS_PATH}" "${RESOURCES_DIR}/AppIcon.icns"
printf "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# Auto-detect Developer ID Application or Apple Development signing identity unless overridden
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "${SIGN_IDENTITY}" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Developer ID Application:' | sed -E 's/.*"([^"]+)".*/\1/' || true)"
fi
if [[ -z "${SIGN_IDENTITY}" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Apple Development:' | sed -E 's/.*"([^"]+)".*/\1/' || true)"
fi

if [[ -n "${SIGN_IDENTITY}" ]]; then
  echo "==> Signing ${APP_BUNDLE} with identity: ${SIGN_IDENTITY} (Hardened Runtime)..."
  codesign --force --deep --options runtime --timestamp \
    --entitlements "${PROJECT_ROOT}/Lada/Resources/Lada.entitlements" \
    --sign "${SIGN_IDENTITY}" \
    "${APP_BUNDLE}"
else
  echo "==> No Developer ID / Apple Development identity found; applying ad-hoc signature..."
  codesign --force --deep --sign - \
    --entitlements "${PROJECT_ROOT}/Lada/Resources/Lada.entitlements" \
    "${APP_BUNDLE}"
fi

echo "==> Verifying application bundle code signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

echo "==> Creating distributable disk image at ${DMG_PATH}..."
STAGE_DIR="${BUILD_DIR}/dmg-staging"
rm -rf "${STAGE_DIR}" "${DMG_PATH}" "${ZIP_PATH}"
mkdir -p "${STAGE_DIR}"
cp -R "${APP_BUNDLE}" "${STAGE_DIR}/"
ln -s /Applications "${STAGE_DIR}/Applications"
hdiutil create -volname "Låda" -srcfolder "${STAGE_DIR}" -ov -format UDZO "${DMG_PATH}" >/dev/null
rm -rf "${STAGE_DIR}"

if [[ -n "${SIGN_IDENTITY}" ]]; then
  echo "==> Signing disk image ${DMG_PATH} with identity: ${SIGN_IDENTITY}..."
  codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG_PATH}"
  codesign --verify --verbose=2 "${DMG_PATH}"
fi

echo "==> Creating signed ZIP archive at ${ZIP_PATH}..."
ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

echo "==> Successfully built and signed:"
echo "    App Bundle: ${APP_BUNDLE}"
echo "    DMG Image:  ${DMG_PATH}"
echo "    ZIP Build:  ${ZIP_PATH}"
