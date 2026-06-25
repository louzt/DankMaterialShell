import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

BasePill {
    id: root

    property bool showPercentage: true
    property bool showIcon: true
    property var toggleProcessList
    property var popoutTarget: null
    property var widgetData: null
    property bool minimumWidth: (widgetData && widgetData.minimumWidth !== undefined) ? widgetData.minimumWidth : true

    signal cpuTempClicked

    Component.onCompleted: {
        DgopService.addRef(["cpu"]);
    }
    Component.onDestruction: {
        DgopService.removeRef(["cpu"]);
    }

    content: Component {
        Item {
            implicitWidth: root.isVerticalOrientation ? (root.widgetThickness - root.horizontalPadding * 2) : cpuTempRow.implicitWidth
            implicitHeight: root.isVerticalOrientation ? cpuTempColumn.implicitHeight : cpuTempRow.implicitHeight

            Column {
                id: cpuTempColumn
                visible: root.isVerticalOrientation
                anchors.centerIn: parent
                spacing: 1

                DankIcon {
                    name: "device_thermostat"
                    size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: DgopService.cpuTemperatureColor(Theme.widgetIconColor, Theme.tempWarning, Theme.tempDanger)
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: DgopService.formatTemperature(DgopService.cpuTemperature, "", "--")
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    color: Theme.widgetTextColor
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Row {
                id: cpuTempRow
                visible: !root.isVerticalOrientation
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    id: cpuTempIcon
                    name: "device_thermostat"
                    size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: DgopService.cpuTemperatureColor(Theme.widgetIconColor, Theme.tempWarning, Theme.tempDanger)
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    id: textBox
                    anchors.verticalCenter: parent.verticalCenter

                    implicitWidth: root.minimumWidth ? Math.max(tempBaseline.width, cpuTempText.paintedWidth) : cpuTempText.paintedWidth
                    implicitHeight: cpuTempText.implicitHeight

                    width: implicitWidth
                    height: implicitHeight

                    StyledTextMetrics {
                        id: tempBaseline
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        text: "88°"
                    }

                    StyledText {
                        id: cpuTempText
                        text: DgopService.formatTemperature(DgopService.cpuTemperature)
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: Theme.widgetTextColor

                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideNone
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onPressed: mouse => {
            root.triggerRipple(this, mouse.x, mouse.y);
            cpuTempClicked();
        }
    }
}
