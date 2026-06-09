#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-${APP_PATH:-}}"
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-work.sangwoo.DragDrop}"

usage() {
    echo "usage: $0 /path/to/DragDrop.app" >&2
    echo "       APP_PATH=/path/to/DragDrop.app $0" >&2
}

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

if [ "${APP_PATH}" = "--help" ] || [ "${APP_PATH}" = "-h" ]; then
    usage
    exit 0
fi

if [ -z "${APP_PATH}" ]; then
    usage
    exit 2
fi

if [ ! -d "${APP_PATH}" ]; then
    fail "app bundle not found: ${APP_PATH}"
fi

INFO_PLIST="${APP_PATH}/Contents/Info.plist"
if [ ! -f "${INFO_PLIST}" ]; then
    fail "Info.plist not found: ${INFO_PLIST}"
fi

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "${INFO_PLIST}")"
if [ "${BUNDLE_ID}" != "${EXPECTED_BUNDLE_ID}" ]; then
    fail "unexpected bundle identifier: ${BUNDLE_ID} (expected ${EXPECTED_BUNDLE_ID})"
fi

echo "==> Verifying code signature"
codesign --verify --strict --verbose=2 "${APP_PATH}"

SIGNING_DETAILS="$(codesign -dvvv "${APP_PATH}" 2>&1)"
echo "${SIGNING_DETAILS}"

if echo "${SIGNING_DETAILS}" | grep -q "Signature=adhoc"; then
    fail "release app is ad-hoc signed"
fi

if ! echo "${SIGNING_DETAILS}" | grep -q "Authority=Developer ID Application"; then
    fail "release app is not signed with a Developer ID Application identity"
fi

if ! echo "${SIGNING_DETAILS}" | grep -q "TeamIdentifier="; then
    fail "release app has no TeamIdentifier"
fi

if ! echo "${SIGNING_DETAILS}" | grep -q "flags=.*runtime"; then
    fail "hardened runtime is not enabled"
fi

echo "==> Checking entitlements"
ENTITLEMENTS="$(codesign -d --entitlements :- "${APP_PATH}" 2>&1 || true)"
echo "${ENTITLEMENTS}"

if echo "${ENTITLEMENTS}" | grep -A1 "com.apple.security.get-task-allow" | grep -q "<true/>"; then
    fail "release app has get-task-allow enabled"
fi

echo "==> Assessing Gatekeeper acceptance"
spctl --assess --type execute --verbose=4 "${APP_PATH}"

echo "==> Release validation passed: ${APP_PATH}"
