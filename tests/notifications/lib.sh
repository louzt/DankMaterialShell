#!/usr/bin/env bash
# Shared helpers for the hardening/notification-suite test suite.
# Source me from any test_*.sh; do not run me directly.

set -euo pipefail

# Resolve the repo root from any test_*.sh by walking up to a directory that
# contains "quickshell/". Caches in REPO_ROOT for the rest of the run.
REPO_ROOT="${REPO_ROOT:-}"
if [[ -z "${REPO_ROOT}" ]]; then
    _here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _cur="${_here}"
    while [[ "${_cur}" != "/" ]]; do
        if [[ -d "${_cur}/quickshell" ]]; then
            REPO_ROOT="${_cur}"
            break
        fi
        _cur="$(dirname "${_cur}")"
    done
    if [[ -z "${REPO_ROOT}" ]]; then
        echo "FAIL: could not locate repo root from ${_here}" >&2
        exit 2
    fi
    export REPO_ROOT
fi

# Path to the QML file under test, or die with a clear message.
require_file() {
    local rel="$1"
    local abs="${REPO_ROOT}/${rel}"
    if [[ ! -f "${abs}" ]]; then
        echo "FAIL: missing file ${rel}" >&2
        exit 2
    fi
    printf '%s' "${abs}"
}

# assert_file_contains <file> <regex> <label>
#   PASSes silently on match, FAILs with a labelled message otherwise.
assert_file_contains() {
    local file="$1" pattern="$2" label="$3"
    if grep -Eq -- "${pattern}" "${file}"; then
        return 0
    fi
    echo "FAIL: ${label}" >&2
    echo "  file:    ${file}" >&2
    echo "  pattern: ${pattern}" >&2
    return 1
}

# assert_file_contains_count <file> <regex> <expected_n> <label>
assert_file_contains_count() {
    local file="$1" pattern="$2" expected="$3" label="$4"
    local actual
    actual="$(grep -Ec -- "${pattern}" "${file}" || true)"
    if [[ "${actual}" -eq "${expected}" ]]; then
        return 0
    fi
    echo "FAIL: ${label}" >&2
    echo "  file:     ${file}" >&2
    echo "  pattern:  ${pattern}" >&2
    echo "  expected: ${expected} match(es)" >&2
    echo "  actual:   ${actual} match(es)" >&2
    return 1
}

# assert_file_not_contains <file> <regex> <label>
assert_file_not_contains() {
    local file="$1" pattern="$2" label="$3"
    if grep -Eq -- "${pattern}" "${file}"; then
        echo "FAIL: ${label} (pattern matched, expected no match)" >&2
        echo "  file:    ${file}" >&2
        echo "  pattern: ${pattern}" >&2
        return 1
    fi
    return 0
}
