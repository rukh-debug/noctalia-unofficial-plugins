import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""

    function _settingValue(key, fallback) {
        var value = pluginApi?.pluginSettings?.[key]
        return value !== undefined && value !== null ? value : fallback
    }

    function _normaliseIconColorKey(key) {
        switch (String(key || "")) {
        case "mPrimary":
        case "primary":
            return "primary"
        case "mSecondary":
        case "secondary":
            return "secondary"
        case "mTertiary":
        case "tertiary":
            return "tertiary"
        case "error":
        case "mError":
            return "error"
        case "mOnSurface":
        case "mOnSurfaceVariant":
        case "none":
            return "none"
        default:
            return "primary"
        }
    }

    // Per-screen sizing (required by Noctalia bar widget spec)
    readonly property string screenName:  screen?.name ?? ""
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize:   Style.getBarFontSizeForScreen(screenName)
    readonly property var widgetDefaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})
    readonly property string iconName:
        _settingValue("barWidgetIconName", widgetDefaults.barWidgetIconName || "device-tv")
    readonly property string widgetText:
        _settingValue("barWidgetText", widgetDefaults.barWidgetText || "AnimeReloaded")
    readonly property string iconColorKey:
        _normaliseIconColorKey(_settingValue("barWidgetIconColor", widgetDefaults.barWidgetIconColor || "primary"))
    readonly property color resolvedIconColor: Color.resolveColorKey(iconColorKey)

    readonly property real contentWidth:  row.implicitWidth + Style.marginM * 2
    readonly property real contentHeight: capsuleHeight

    implicitWidth:  contentWidth
    implicitHeight: contentHeight

    // Visual capsule — centred within the full click area
    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width,  width)
        y: Style.pixelAlignCenter(parent.height, height)
        width:  root.contentWidth
        height: root.contentHeight
        color:  mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
        radius: Style.radiusL
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Style.marginXS

            NIcon {
                icon: root.iconName
                color: mouseArea.containsMouse ? Color.mOnHover : root.resolvedIconColor
            }
            NText {
                visible: root.widgetText.length > 0
                text: root.widgetText
                color: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
                pointSize: root.barFontSize
            }
        }
    }

    NPopupContextMenu {
        id: contextMenu

        model: [
            {
                "label": "Widget Settings",
                "action": "widget-settings",
                "icon": "settings"
            }
        ]

        onTriggered: action => {
            contextMenu.close()
            PanelService.closeContextMenu(root.screen)

            if (action === "widget-settings" && pluginApi?.manifest)
                BarService.openPluginSettings(root.screen, pluginApi.manifest)
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: TooltipService.show(root, "AnimeReloaded browser", BarService.getTooltipDirection())
        onExited:  TooltipService.hide()
        onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                if (pluginApi) pluginApi.togglePanel(root.screen)
            } else if (mouse.button === Qt.RightButton) {
                PanelService.showContextMenu(contextMenu, root, root.screen)
            }
        }
    }
}
