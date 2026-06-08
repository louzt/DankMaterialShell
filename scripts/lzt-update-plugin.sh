#!/usr/bin/env bash
# lzt-update-plugin.sh — hot-reload wrapper for any DMS plugin
#
# Usage:
#   lzt-update-plugin.sh <plugin-id>           # one-shot reload
#   lzt-update-plugin.sh <plugin-id> --watch   # watch the plugin dir, reload on change
#   lzt-update-plugin.sh --all                 # rescan every known plugin
#   lzt-update-plugin.sh --self-test           # verify the wrapper itself
#
# Background:
#   hardening/notification-suite added a defensive forceRescanPlugin
#   that purges all per-plugin in-memory state (daemon/widget/launcher/
#   desktop Components + live QObject instances) before re-reading the
#   manifest. Without that purge, a manifest type change (daemon ->
#   widget) kept the old daemon PanelWindow alive on top of the new
#   bar widget. With the purge, `qs ipc call plugins rescan <id>` is
#   the canonical "reload this plugin completely" command.
#
#   This wrapper makes that command ergonomic, watchable, and CI-friendly.
set -euo pipefail

PLUGIN_DIR="${HOME}/.config/DankMaterialShell/plugins"
QS_PID="$(pgrep -f "qs -p" | grep -v zsh | head -1)"

red()    { printf "\033[31m%s\033[0m\n" "$*"; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
bold()   { printf "\033[1m%s\033[0m\n" "$*"; }

die() { red "error: $*" >&2; exit 1; }

[ -n "${QS_PID}" ] || die "no qs process running (pgrep -f 'qs -p' returned nothing)"

cmd="${1:-}"
shift || true

case "${cmd}" in
    --self-test)
        bold "[lzt-update-plugin] self-test"
        if ! command -v qs >/dev/null 2>&1; then
            red "  qs not in PATH"; exit 1
        fi
        if ! command -v inotifywait >/dev/null 2>&1; then
            yellow "  inotifywait not installed (--watch needs inotify-tools)"
        fi
        if [ -z "${QS_PID}" ]; then
            yellow "  no qs process running (start qs and retry for a full test)"
        else
            local_list=$(qs ipc --pid "${QS_PID}" call plugins list 2>&1 | wc -l)
            green "  qs pid=${QS_PID} plugins_known=${local_list}"
        fi
        green "  wrapper OK"
        exit 0
        ;;
    --all)
        bold "[lzt-update-plugin] rescanning every known plugin"
        mapfile -t ids < <(qs ipc --pid "${QS_PID}" call plugins list 2>&1 | awk '{print $1}')
        for id in "${ids[@]}"; do
            printf "  %-32s " "${id}"
            if qs ipc --pid "${QS_PID}" call plugins rescan "${id}" >/dev/null 2>&1; then
                green "OK"
            else
                red "FAIL"
            fi
        done
        exit 0
        ;;
    --watch)
        plugin_id="${1:?usage: lzt-update-plugin.sh <id> --watch}"
        shift
        command -v inotifywait >/dev/null 2>&1 || die "inotifywait not installed (apt install inotify-tools)"
        watch_dir="${PLUGIN_DIR}/${plugin_id}"
        [ -d "${watch_dir}" ] || die "plugin dir not found: ${watch_dir}"
        bold "[lzt-update-plugin] watching ${watch_dir} (Ctrl-C to stop)"
        inotifywait -m -r -e modify,create,delete,move \
            --include '\.(qml|js|json)$' \
            "${watch_dir}" | while read -r path event file; do
            printf "  %s %s/%s -> rescan %s\n" "${event}" "${path}" "${file}" "${plugin_id}"
            if qs ipc --pid "${QS_PID}" call plugins rescan "${plugin_id}" 2>&1; then
                green "  -> reloaded"
            else
                red "  -> rescan failed (check qs log)"
            fi
        done
        exit 0
        ;;
    --help|-h|"")
        cat <<EOF
lzt-update-plugin.sh — hot-reload wrapper for any DMS plugin

Usage:
  lzt-update-plugin.sh <plugin-id>           # one-shot reload
  lzt-update-plugin.sh <plugin-id> --watch   # watch + auto-reload
  lzt-update-plugin.sh --all                 # rescan every known plugin
  lzt-update-plugin.sh --self-test           # verify the wrapper
  lzt-update-plugin.sh --help                # this message

Environment:
  PLUGIN_DIR  override plugin discovery (default: ~/.config/DankMaterialShell/plugins)

Requires:
  qs (Quickshell 0.3.0+ with the scan-ipc IPC handlers from PR #2601)
  inotifywait (for --watch; apt install inotify-tools)
EOF
        exit 0
        ;;
    *)
        plugin_id="${cmd}"
        [ -d "${PLUGIN_DIR}/${plugin_id}" ] || die "plugin dir not found: ${PLUGIN_DIR}/${plugin_id}"
        bold "[lzt-update-plugin] rescan ${plugin_id} (pid=${QS_PID})"
        if out=$(qs ipc --pid "${QS_PID}" call plugins rescan "${plugin_id}" 2>&1); then
            green "  ${out}"
            qs ipc --pid "${QS_PID}" call plugins status "${plugin_id}" 2>&1 | sed 's/^/  /'
        else
            red "  ${out}"
            exit 1
        fi
        ;;
esac
