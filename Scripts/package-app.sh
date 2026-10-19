#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
BUILD_DIR="${PROJECT_ROOT}/build"
APP_BUNDLE="${BUILD_DIR}/Lada.app"
DMG_PATH="${BUILD_DIR}/Lada-1.5.0.dmg"
ZIP_PATH="${BUILD_DIR}/Lada-1.5.0-macOS-arm64.zip"
NOTARIZE_ZIP="${BUILD_DIR}/Lada-notarize.zip"
NOTARY_PROFILE="${LADA_NOTARY_PROFILE:-MySpacesNotary}"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICNS_PATH="${PROJECT_ROOT}/Lada/Resources/AppIcon.icns"

# Clean up any legacy non-ASCII build outputs
rm -rf "${BUILD_DIR}/Låda.app" "${BUILD_DIR}/Låda-1.5.0.dmg" "${BUILD_DIR}/Låda-1.5.0-macOS-arm64.zip"

if [[ ! -f "${ICNS_PATH}" ]]; then
  echo "==> Generating Technical Nordic macOS AppIcon.icns..."
  ICONSET_DIR="${BUILD_DIR}/AppIcon.iconset"
  mkdir -p "${BUILD_DIR}"
  swift "${SCRIPT_DIR}/generate-app-icon.swift" "${ICONSET_DIR}"
  iconutil -c icns "${ICONSET_DIR}" -o "${ICNS_PATH}"
  rm -rf "${ICONSET_DIR}"
fi

echo "==> Building Lada (Release configuration)..."
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

if [[ "${SIGN_IDENTITY}" == *"Developer ID Application"* ]]; then
  echo "==> Creating clean archive (--norsrc --noextattr) for Apple Notary Service (profile: ${NOTARY_PROFILE})..."
  rm -f "${NOTARIZE_ZIP}"
  ditto -c -k --norsrc --noextattr --keepParent "${APP_BUNDLE}" "${NOTARIZE_ZIP}"
  xcrun notarytool submit "${NOTARIZE_ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait
  rm -f "${NOTARIZE_ZIP}"

  echo "==> Stapling notarization ticket to ${APP_BUNDLE}..."
  xcrun stapler staple "${APP_BUNDLE}"
  xcrun stapler validate "${APP_BUNDLE}"
fi

echo "==> Creating clean distribution ZIP archive (--norsrc --noextattr) at ${ZIP_PATH}..."
rm -f "${ZIP_PATH}"
ditto -c -k --norsrc --noextattr --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

APPLE_DOUBLE_COUNT="$(unzip -l "${ZIP_PATH}" | grep -c '/\._' || true)"
if [[ "${APPLE_DOUBLE_COUNT}" -ne 0 ]]; then
  echo "Error: Distribution zip still contains ${APPLE_DOUBLE_COUNT} AppleDouble (._) files!" >&2
  exit 1
fi

echo "==> Creating distributable disk image at ${DMG_PATH}..."
STAGE_DIR="${BUILD_DIR}/dmg-staging"
rm -rf "${STAGE_DIR}" "${DMG_PATH}"
mkdir -p "${STAGE_DIR}"
ditto --norsrc --noextattr "${APP_BUNDLE}" "${STAGE_DIR}/Lada.app"
ln -s /Applications "${STAGE_DIR}/Applications"
hdiutil create -volname "Lada" -srcfolder "${STAGE_DIR}" -ov -format UDZO "${DMG_PATH}" >/dev/null
rm -rf "${STAGE_DIR}"

if [[ -n "${SIGN_IDENTITY}" ]]; then
  echo "==> Signing disk image ${DMG_PATH} with identity: ${SIGN_IDENTITY}..."
  codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG_PATH}"
  codesign --verify --verbose=2 "${DMG_PATH}"
fi

if [[ "${SIGN_IDENTITY}" == *"Developer ID Application"* ]]; then
  echo "==> Notarizing and stapling disk image ${DMG_PATH}..."
  xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${DMG_PATH}"
  xcrun stapler validate "${DMG_PATH}"

  echo "==> Running Gatekeeper & syspolicy_check distribution verification..."
  spctl -a -t exec -vv "${APP_BUNDLE}"
  syspolicy_check distribution "${APP_BUNDLE}"
fi

echo "==> Successfully built, signed, notarized, and packaged (0 AppleDouble files):"
echo "    App Bundle: ${APP_BUNDLE}"
echo "    DMG Image:  ${DMG_PATH}"
echo "    ZIP Build:  ${ZIP_PATH}"
