import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "wallpaperHealthDaemon"

    StyledText {
        text: "Wallpaper Health Daemon"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        text: "Polls the LZT wallpaper override file (~/.local/state/lzt/wallpaper-override.json) " +
              "and yields the Background layer to external backends (swww, linux-wallpaperengine, etc.) " +
              "launched via waypaper. When the external process dies, DMS re-claims the layer and re-renders " +
              "its configured wallpaper as a fallback."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
        wrapMode: Text.WordWrap
        width: parent.width
    }

    SliderSetting {
        settingKey: "pollIntervalMs"
        label: "Poll Interval"
        description: "How often to check the override file and verify PIDs are still alive. " +
                     "Lower = faster fallback when an external backend dies, but more CPU. " +
                     "Higher = less responsive but cheaper."
        defaultValue: 10000
        minimum: 1000
        maximum: 60000
        unit: "ms"
    }
}
