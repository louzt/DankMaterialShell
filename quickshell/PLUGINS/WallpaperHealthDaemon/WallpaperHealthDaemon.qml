import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root
    pluginId: "wallpaperHealthDaemon"

    readonly property string overridePath: {
        if (Quickshell.env("LZT_WALLPAPER_OVERRIDE_PATH")) {
            return Quickshell.env("LZT_WALLPAPER_OVERRIDE_PATH");
        }
        // StandardPaths.writableLocation returns a QML `url` (which is its
        // own type with no string methods). Concatenation with a string
        // coerces it via toString(), which yields `file:///path`. We slice
        // off the `file://` prefix to feed /usr/bin/cat a real path.
        let raw = "" + StandardPaths.writableLocation(StandardPaths.GenericStateLocation);
        const prefix = "file://";
        if (raw.indexOf(prefix) === 0) {
            raw = raw.substring(prefix.length);
        }
        return raw + "/lzt/wallpaper-override.json";
    }

    readonly property int pollIntervalMs: (pluginData && pluginData.pollIntervalMs) || 10000

    // Run an immediate check on startup, then poll.
    Timer {
        interval: root.pollIntervalMs
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.readFile()
    }

    function readFile() {
        readProcess.running = true;
    }

    Process {
        id: readProcess
        command: ["/usr/bin/cat", root.overridePath]
        stdout: StdioCollector {
            id: readCollector
            onStreamFinished: {
                root.handleRawJson(text);
            }
        }
        stderr: StdioCollector {
            id: readStderr
            onStreamFinished: {
                if (text && text.trim()) {
                    console.warn("WallpaperHealthDaemon: cat stderr:", text.trim().slice(0, 200));
                }
            }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                // File missing or unreadable — treat as empty (no overrides).
                root.applyOverrides({});
            }
        }
    }

    function handleRawJson(text) {
        if (!text || !text.trim()) {
            applyOverrides({});
            return;
        }
        try {
            const data = JSON.parse(text);
            const overrides = (data && data.overrides) || {};
            applyOverrides(overrides);
        } catch (e) {
            // Malformed JSON: treat as empty so we don't yield incorrectly.
            applyOverrides({});
        }
    }

    function applyOverrides(overrides) {
        const pids = [];
        for (const monitor in overrides) {
            const entry = overrides[monitor];
            if (entry && typeof entry.pid === "number" && entry.pid > 0) {
                pids.push(entry.pid);
            }
        }
        if (pids.length === 0) {
            SessionData.externalWallpaperOverrides = {};
            console.info("WallpaperHealthDaemon: yielding nothing (DMS owns all layers)");
            return;
        }
        // Hand off to the liveness check. Build the command directly so we
        // don't depend on Process.environment, which is awkward in QML.
        const pidArgs = pids.map(p => String(p));
        const aliveExpr = pidArgs.map(p => `[ -d \"/proc/${p}\" ] && echo ${p}`).join("; ");
        livenessCheck.candidates = overrides;
        livenessCheck.command = ["sh", "-c", aliveExpr];
        livenessCheck.running = true;
    }

    Process {
        id: livenessCheck
        property var candidates: ({})

        stdout: StdioCollector {
            id: livenessCollector
            onStreamFinished: {
                const aliveList = (text || "").split("\n")
                    .map(s => s.trim())
                    .filter(Boolean);
                const aliveSet = {};
                for (const pid of aliveList) {
                    aliveSet[pid] = true;
                }
                const live = {};
                const droppedMonitors = [];
                for (const monitor in livenessCheck.candidates) {
                    const entry = livenessCheck.candidates[monitor];
                    if (entry && aliveSet[String(entry.pid)]) {
                        live[monitor] = entry;
                    } else {
                        droppedMonitors.push(`${monitor}(${entry ? entry.pid : "?"})`);
                    }
                }
                console.info("WallpaperHealthDaemon: alive=", Object.keys(live).join(",") || "(none)",
                    "dropped=", droppedMonitors.join(",") || "(none)");
                SessionData.externalWallpaperOverrides = live;
            }
        }
        stderr: StdioCollector {}
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                // Liveness check failed — fail open (treat all as dead so
                // DMS re-renders). Safer than failing closed (a dead
                // external keeps the layer yielded forever).
                SessionData.externalWallpaperOverrides = {};
            }
        }
    }

    Component.onCompleted: {
        console.info("WallpaperHealthDaemon: monitoring", root.overridePath,
            "every", root.pollIntervalMs, "ms");
    }

    Component.onDestruction: {
        console.info("WallpaperHealthDaemon: stopped");
    }
}
