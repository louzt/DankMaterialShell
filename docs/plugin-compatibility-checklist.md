# Plugin compatibility checklist

For authors hardening or porting DMS plugins. Each item was a real bug
encountered during `hardening/notification-suite` development
(2026-06-08). Use `lzt-update-plugin.sh <id>` from
`scripts/lzt-update-plugin.sh` to reload after each change. When you're
editing from inside Claude Code, the `post-tool-qml-reload.sh` hook
(in `~/.claude/plugins/lzt-harness/hooks/`) auto-fires the rescan on
`Edit`/`Write`/`MultiEdit` of any `*.qml`/`*.js`/`plugin.json` under
`*/plugins/<id>/*` — no manual step needed. The hook only emits a
hint (it never blocks), and warns you explicitly on manifest edits.

## 1. Settings persistence (the v0.3 bug)

❌ **DON'T**: `pluginData.someKey = newValue` inside `onAccepted` /
`onToggled`. The `pluginData` object is a deep-cloned snapshot
(`SettingsData.qml:2940-2943`); mutations are silently dropped.

✅ **DO**: `SettingsData.setPluginSetting("<pluginId>", "someKey", newValue)`
and read with `SettingsData.getPluginSetting("<pluginId>", "someKey", default)`.

Detection: grep for `pluginData\.\w+ ?=` in your QML files.

## 2. Native popup suppression (the v0.4 design)

❌ **DON'T**: call `NotificationService.disablePopups(true)` from a
plugin and assume it's the only way. It is a **global** kill switch
— every screen on every bar loses native popups.

✅ **DO**: prefer the per-screen variant from
`hardening/notification-suite`:
```qml
if (notifService.setScreenPopupsDisabled) {
    notifService.setScreenPopupsDisabled(parentScreen.name, true);
} else if (notifService.disablePopups) {
    // Fallback for stock DMS without the hardening branch
    notifService.disablePopups(true);
}
```

Always pair the set with a revert in `Component.onDestruction` so the
screen is not left blocked if the plugin crashes or the user
disables it.

## 3. Read state tracking (don't fork it)

❌ **DON'T**: maintain a private `Set<id>` in `plugin_settings.json`
just to know "which notifications have I shown the user". Multiple
plugins will diverge.

✅ **DO**: use the centralized map from the fork:
```qml
if (notifService.markRead) {
    notifService.markRead(wrapper.id, Date.now());
} else {
    // Fallback for stock DMS
    SettingsData.setPluginSetting("notificationIsland", "readIds", ...);
}
```

## 4. Plugin type changes (the daemon→widget bug)

❌ **DON'T**: change `type` in `plugin.json` (e.g. `daemon` → `widget`)
and expect `qs ipc call plugins reload <id>` to take effect. The
`reload` IPC re-evaluates the QML but the old type's Component stays
mounted on top of the new one.

✅ **DO**: use `qs ipc call plugins rescan <id>` after a type change,
or use the wrapper from `scripts/lzt-update-plugin.sh`. Even better,
`hardening/notification-suite` patches `forceRescanPlugin` to purge
all per-plugin in-memory state (daemon, widget, launcher, desktop
maps + the live QObject instance) before re-reading the manifest.

If you are on stock DMS and see "double bubbles" or "plugin loaded
as both daemon and widget" in `qs log`, you hit this bug. Fix:
1. `kill $(pgrep -f "qs -p" | grep -v zsh | head -1)` — full qs restart
2. `rm -rf ~/.cache/quickshell/qmlcache/*` — clear compiled QML cache
3. Relaunch `qs -p ~/.config/quickshell/dms &`

## 5. Bar widget placement (the in-bar vs on-top question)

When `type: "widget"`, the plugin's `horizontalBarPill` (or
`verticalBarPill`) Component is mounted **inside** the bar's
LeftSection / CenterSection / RightSection (`DankBarContent.qml:480-664`).
The pill is automatically sized to `barThickness × iconSize`. If the
pill looks oversized or floating, check:

1. `Component.onDestruction` runs on widget teardown — make sure
   your pill doesn't leak timers or Connections.
2. `Connections { target: root.item; enabled: false }` in nested
   children — orphan Connections leak across reloads.
3. The bar's `screenPreferences` filter — if the bar is on all 3
   screens, the widget appears 3 times. Use per-bar
   `screenPreferences` to constrain.

## 6. Lint and parse

Run `make lint-qml` in the DMS repo before committing. The
hardening branch's CI runs `qmllint6` over the entrypoints
(`shell.qml`, `DMSShell.qml`, `DMSGreeter.qml`). Local execution
needs `Qt 6 qmllint` installed; if missing, defer to CI and post the
warning in the PR body (per the `dms-contributing-checklist` memory).

## 7. Capability declarations

Keep `capabilities` minimal and accurate. `notification-overlay` was
removed from the hardening branch's manifest because it is not
declared as a known capability in `PluginService.qml`. Extra
capabilities confuse the widget picker.

## 8. Permissions

`"permissions": ["settings_read", "settings_write"]` is enough for
most plugins. If you need a custom permission (e.g. `notifications_send`),
add it to the `permissions` array AND audit the PluginService gate.
Otherwise the call will be silently rejected.

## 9. Test on clean profile

Before publishing:
```bash
mv ~/.config/DankMaterialShell/plugins/MyPlugin{,.bak}
ln -s /path/to/dev/MyPlugin ~/.config/DankMaterialShell/plugins/MyPlugin
qs -p ~/.config/quickshell/dms  # foreground, watch for QML errors
```

If the plugin still works in a fresh profile, it's likely robust.

## 10. Ship-pr

When the plugin is mature and the branch is clean, use
`~/.claude/plugins/lzt-harness/scripts/loust-ship-pr.sh` (or `/ship-pr`
slash command) to prepare a PR. The `change-batches` Makefile target
in `~/Proyectos/Labs/Compliance-Verification-Harness/` groups commits
by prefix and suggests a PR split. Stage-local-first rule applies —
no push without explicit approval.

## 11. Auto-reload loop (the in-editor dev cycle)

There is a `PostToolUse` hook in `~/.claude/plugins/lzt-harness/hooks/post-tool-qml-reload.sh`
that fires `qs ipc call plugins rescan <id>` automatically every time
Claude Code (or you via the Edit/Write tools) saves a `.qml`, `.js`, or
`plugin.json` inside a DMS plugin dir. So the loop becomes:

1. Save `.qml` → hook rescan, you see the change in 200 ms.
2. Manifest edit → hook warns, you decide whether to do the full
   `kill -9 qs && rm -rf ~/.cache/quickshell/qmlcache/* && relaunch`
   (manifest type changes always need this; setting additions don't).
3. Subagent edit (Task tool spawning) → the hook also fires for
   subagent file edits, so the reload happens automatically for any
   file the agent touches. No special routing needed.

Disable per-invocation: `LZT_QML_RELOAD_DISABLE=1 <your command>`.
Dry-run: `LZT_QML_RELOAD_DRY_RUN=1 <command>` to log the would-be
rescan without firing it (useful when debugging the hook itself).
Self-test: `LZT_QML_RELOAD_SELF_TEST=1 $0 < /dev/null`.
