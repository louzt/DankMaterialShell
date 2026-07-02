#!/usr/bin/env bash
# test_per_screen_popups.sh
# Concern A.1: per-screen popup suppression map + set/clear/is API.
# Source: commit 28bbc5e2 — NotificationService.qml.
# Validates that the documented API and the gate that consumes it are present.

set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

SVC="$(require_file "quickshell/Services/NotificationService.qml")"

# 1. The property must exist and default to an empty object so the per-screen
#    gate in onNotification has something to look up.
assert_file_contains \
    "${SVC}" \
    'property var perScreenPopupsDisabled: \(\{\}\)' \
    "perScreenPopupsDisabled map must default to an empty object"

# 2. The activeScreen property must read Quickshell.screen.name with a
#    try/catch fallback to "_all" so plugin callers never see undefined.
assert_file_contains \
    "${SVC}" \
    'readonly property string activeScreen:' \
    "activeScreen readonly string property must be defined"

assert_file_contains \
    "${SVC}" \
    'Quickshell\.screen\.name \|\| "_all"' \
    "activeScreen must fall back to _all when screen name is unavailable"

# 3. The three documented accessors must be present and named exactly as the
#    commit message and the plugin contract expose.
assert_file_contains \
    "${SVC}" \
    'function setScreenPopupsDisabled\(screenName, disabled\)' \
    "setScreenPopupsDisabled(screenName, disabled) function must exist"

assert_file_contains \
    "${SVC}" \
    'function clearScreenPopupsDisabled\(\)' \
    "clearScreenPopupsDisabled() function must exist"

assert_file_contains \
    "${SVC}" \
    'function isScreenPopupsDisabled\(screenName\)' \
    "isScreenPopupsDisabled(screenName) function must exist"

# 4. setScreenPopupsDisabled must default the screen name to activeScreen
#    when the caller omits it (so plugins can call with no args).
assert_file_contains \
    "${SVC}" \
    'const name = screenName \|\| root\.activeScreen' \
    "setScreenPopupsDisabled must default to activeScreen when arg is empty"

# 5. The onNotification gate must consult both the global popupsDisabled and
#    the per-screen map (and the _all key), otherwise the feature is dead code.
assert_file_contains \
    "${SVC}" \
    'perScreenPopupsDisabled\[_activeScreen\] === true' \
    "gate must check perScreenPopupsDisabled[activeScreen]"

assert_file_contains \
    "${SVC}" \
    'perScreenPopupsDisabled\["_all"\] === true' \
    "gate must also honor the _all key"

# 6. The gate must short-circuit when either switch is set, so the popup is
#    blocked from being enqueued when popups are suppressed for the screen.
assert_file_contains \
    "${SVC}" \
    '!root\.popupsDisabled\s*$' \
    "gate must check global popupsDisabled"

echo PASS
