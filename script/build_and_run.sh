#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="DragDrop"
BUNDLE_ID="work.sangwoo.DragDrop"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_DIR}/${APP_NAME}.xcodeproj"
SCHEME="${SCHEME:-${APP_NAME}}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS,arch=$(uname -m)}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${PROJECT_DIR}/build}"
APP_BUNDLE="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
APP_BINARY="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-10}"

usage() {
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--build-only]" >&2
}

if [ ! -d "${PROJECT_PATH}" ]; then
    echo "ERROR: Xcode project not found at ${PROJECT_PATH}" >&2
    exit 1
fi

stop_app() {
    if pgrep -x "${APP_NAME}" > /dev/null 2>&1; then
        echo "==> Stopping running ${APP_NAME}..."
        killall "${APP_NAME}" 2>/dev/null || true
        sleep 1
    fi
}

build_app() {
    echo "==> Building ${APP_NAME} (${CONFIGURATION})..."
    xcodebuild \
        -project "${PROJECT_PATH}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -destination "${DESTINATION}" \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        build

    if [ ! -d "${APP_BUNDLE}" ]; then
        echo "ERROR: Build product not found at ${APP_BUNDLE}" >&2
        exit 1
    fi

    if [ ! -x "${APP_BINARY}" ]; then
        echo "ERROR: App executable not found at ${APP_BINARY}" >&2
        exit 1
    fi
}

open_app() {
    echo "==> Launching ${APP_NAME}..."
    /usr/bin/open -n "${APP_BUNDLE}"
}

verify_app() {
    local elapsed=0
    while [ "${elapsed}" -lt "${VERIFY_TIMEOUT}" ]; do
        if pgrep -x "${APP_NAME}" > /dev/null; then
            echo "==> Verified running process: ${APP_NAME}"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "ERROR: ${APP_NAME} did not appear within ${VERIFY_TIMEOUT}s" >&2
    return 1
}

stop_app
build_app

if [ "${BUILD_ONLY:-0}" = "1" ] || [ "${MODE}" = "--build-only" ] || [ "${MODE}" = "build-only" ]; then
    echo "==> Build product: ${APP_BUNDLE}"
    exit 0
fi

case "${MODE}" in
    run)
        open_app
        ;;
    --debug|debug)
        lldb -- "${APP_BINARY}"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"${APP_NAME}\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"${BUNDLE_ID}\""
        ;;
    --verify|verify)
        open_app
        verify_app
        ;;
    *)
        usage
        exit 2
        ;;
esac

echo "==> Build product: ${APP_BUNDLE}"
