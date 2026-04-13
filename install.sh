#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="DragDrop"
DEST="/Applications/${APP_NAME}.app"
BUILD_DIR="${PROJECT_DIR}/build"

echo "==> Building ${APP_NAME} (Release)..."
xcodebuild \
    -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    -quiet

BUILT_APP="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "${BUILT_APP}" ]; then
    echo "ERROR: Build product not found at ${BUILT_APP}"
    exit 1
fi

# Quit running instance
if pgrep -x "${APP_NAME}" > /dev/null 2>&1; then
    echo "==> Stopping running ${APP_NAME}..."
    killall "${APP_NAME}" 2>/dev/null || true
    sleep 1
fi

echo "==> Installing to ${DEST}..."
rm -rf "${DEST}"
cp -R "${BUILT_APP}" "${DEST}"

echo "==> Launching ${APP_NAME}..."
open "${DEST}"

echo "==> Done."
