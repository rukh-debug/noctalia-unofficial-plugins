import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets

Item {
    id: root

    // Plugin API (injected by PluginService)
    property var pluginApi: null

    // Required properties for bar widgets
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""

    // Per-screen bar properties
    readonly property string screenName: screen?.name ?? ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

    // Settings
    readonly property int updateIntervalMs:
        pluginApi?.pluginSettings?.updateIntervalMs ??
        pluginApi?.manifest?.metadata?.defaultSettings?.updateIntervalMs ??
        200
    readonly property string textColor:
        pluginApi?.pluginSettings?.textColor ??
        pluginApi?.manifest?.metadata?.defaultSettings?.textColor ??
        ""
    readonly property int maxTextLength:
        pluginApi?.pluginSettings?.maxTextLength ??
        pluginApi?.manifest?.metadata?.defaultSettings?.maxTextLength ??
        0
    readonly property bool showDefault:
        pluginApi?.pluginSettings?.showDefault ??
        pluginApi?.manifest?.metadata?.defaultSettings?.showDefault ??
        false

    property string keymodeText: ""

    function normalizeMode(modeText) {
        return (modeText || "").trim();
    }

    function shouldShow(modeText) {
        var normalized = normalizeMode(modeText);
        if (normalized === "" || normalized === "default") {
            return showDefault;
        }
        return true;
    }

    function parseKeymode(outputText) {
        var lines = (outputText || "").split(/\r?\n/);
        var modeByOutput = {};
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (!line) continue;
            var match = line.match(/^(\S+)\s+keymode\s*(.*)$/);
            if (match) {
                var outputName = match[1];
                var mode = (match[2] || "").trim();
                modeByOutput[outputName] = mode;
            }
        }

        if (screenName && modeByOutput[screenName] !== undefined) {
            return modeByOutput[screenName];
        }

        var outputs = Object.keys(modeByOutput);
        if (outputs.length > 0) {
            return modeByOutput[outputs[0]];
        }

        return "";
    }

    function applyMaxLength(text) {
        if (!text) return "";
        if (!maxTextLength || maxTextLength <= 0) return text;
        if (text.length <= maxTextLength) return text;
        if (maxTextLength <= 3) return "...";
        return text.slice(0, maxTextLength - 3) + "...";
    }

    readonly property bool hasKeymode: shouldShow(keymodeText)
    readonly property string displayText: hasKeymode
        ? applyMaxLength(normalizeMode(keymodeText))
        : ""

    // Base text dimensions (before rotation)
    readonly property real textWidth: hasKeymode ? content.implicitWidth : 0
    readonly property real textHeight: hasKeymode ? capsuleHeight : 0

    // Content dimensions (visual capsule size, accounting for rotation)
    readonly property real contentWidth: hasKeymode
        ? (isBarVertical ? textHeight : (textWidth + Style.marginM * 2))
        : 0
    readonly property real contentHeight: hasKeymode
        ? (isBarVertical ? (textWidth + Style.marginM * 2) : textHeight)
        : 0

    // Widget dimensions (extends to full bar height for better click area)
    implicitWidth: contentWidth
    implicitHeight: contentHeight
    visible: hasKeymode

    Timer {
        id: pollTimer
        interval: Math.max(100, updateIntervalMs)
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!keymodeProcess.running) {
                keymodeProcess.exec(["mmsg", "-g"]);
            }
        }
    }

    Process {
        id: keymodeProcess
        running: false
        property string output: ""

        stdout: StdioCollector {
            onStreamFinished: {
                keymodeProcess.output = this.text;
            }
        }

        onExited: function (exitCode, _exitStatus) {
            if (exitCode !== 0) {
                Logger.w("mangowc-keymode-submap", "mmsg exited with code", exitCode);
                return;
            }
            root.keymodeText = parseKeymode(keymodeProcess.output);
        }
    }

    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        color: Style.capsuleColor
        radius: Style.radiusL
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        RowLayout {
            id: content
            anchors.centerIn: parent
            spacing: Style.marginS

            NText {
                text: root.displayText
                color: root.textColor !== "" ? root.textColor : Color.mOnSurface
                pointSize: barFontSize
                font.weight: Font.Medium
                visible: root.displayText !== ""
                rotation: isBarVertical ? -90 : 0
                transformOrigin: Item.Center
            }
        }
    }

    NPopupContextMenu {
        id: contextMenu

        model: [
            {
                "label": "Plugin Settings",
                "action": "plugin-settings",
                "icon": "settings"
            }
        ]

        onTriggered: action => {
            contextMenu.close();
            PanelService.closeContextMenu(screen);

            if (action === "plugin-settings") {
                BarService.openPluginSettings(screen, pluginApi.manifest);
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        hoverEnabled: true

        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
                PanelService.showContextMenu(contextMenu, root, screen);
            }
        }
    }
}
