#!/usr/bin/env bash
# Build GitStatusBar.app from the SwiftPM target.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="release"
BIN_NAME="GitStatusBar"
APP_DIR="${BIN_NAME}.app"

echo "→ swift build -c ${CONFIG}"
BIN_DIR="$(swift build -c "${CONFIG}" --show-bin-path)"
BIN_PATH="${BIN_DIR}/${BIN_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "build failed: binary not at ${BIN_PATH}" >&2
  exit 1
fi

echo "→ assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${BIN_NAME}"
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"

if [[ ! -f "Resources/AppIcon.icns" ]]; then
  echo "→ generating AppIcon.icns"
  swift Resources/make-icon.swift >/dev/null
fi
cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

echo "→ ad-hoc codesign"
codesign --force --sign - "${APP_DIR}" >/dev/null 2>&1 || true

echo "✓ built $(pwd)/${APP_DIR}"
echo "  run with:   open ${APP_DIR}"
echo "  install:    mv ${APP_DIR} /Applications/"
