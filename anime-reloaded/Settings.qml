import QtQuick
import QtCore
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var pluginApi: null
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

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

    function _colorOptionName(key) {
        for (var i = 0; i < colorOptions.length; i++) {
            var option = colorOptions[i] || ({})
            if (String(option.key || "") === _normaliseIconColorKey(key))
                return String(option.name || option.key || "")
        }
        return _normaliseIconColorKey(key)
    }

    function _colorHex(color) {
        var toHex = function(component) {
            var value = Math.max(0, Math.min(255, Math.round(Number(component || 0) * 255)))
            var hex = value.toString(16).toUpperCase()
            return hex.length < 2 ? ("0" + hex) : hex
        }
        return "#" + toHex(color.r) + toHex(color.g) + toHex(color.b)
    }

    function _localPathFromUrl(value) {
        var text = String(value || "").trim()
        if (text.indexOf("file://localhost/") === 0)
            text = text.substring("file://localhost".length)
        else if (text.indexOf("file://") === 0)
            text = text.substring("file://".length)
        return decodeURIComponent(text)
    }

    function _normaliseDirectoryPath(value) {
        var text = String(value || "").trim()
        if (text.length === 0)
            return ""
        if (text.indexOf("file://") === 0)
            text = _localPathFromUrl(text)
        text = text.replace(/\/+$/, "")
        if (text.length === 0)
            return "/"
        return text
    }

    function _pathJoin(base, child) {
        if (!base || base.length === 0)
            return child || ""
        if (!child || child.length === 0)
            return base
        if (base.endsWith("/"))
            return base + child
        return base + "/" + child
    }

    function _defaultDownloadsRoot() {
        var locations = StandardPaths.standardLocations(StandardPaths.DownloadLocation)
        if (locations && locations.length > 0 && String(locations[0] || "").length > 0)
            return String(locations[0])
        var home = String(StandardPaths.writableLocation(StandardPaths.HomeLocation) || "")
        return home.length > 0 ? _pathJoin(home, "Downloads") : ""
    }

    function _defaultEpisodeDownloadPath() {
        var base = _normaliseDirectoryPath(_defaultDownloadsRoot())
        return base.length > 0 ? _pathJoin(base, "AnimeReloaded") : ""
    }

    property string barWidgetIconName:
        _settingValue("barWidgetIconName", defaults.barWidgetIconName || "device-tv")
    property string barWidgetText:
        _settingValue("barWidgetText", defaults.barWidgetText || "AnimeReloaded")
    property string barWidgetIconColor:
        _normaliseIconColorKey(_settingValue("barWidgetIconColor", defaults.barWidgetIconColor || "primary"))
    property string episodeDownloadPath:
        String(_settingValue("episodeDownloadPath", ""))
    readonly property string defaultEpisodeDownloadPath:
        _defaultEpisodeDownloadPath()
    readonly property string effectiveEpisodeDownloadPath:
        _normaliseDirectoryPath(root.episodeDownloadPath).length > 0
            ? _normaliseDirectoryPath(root.episodeDownloadPath)
            : defaultEpisodeDownloadPath

    readonly property var colorOptions: Color.colorKeyModel

    function resetToDefaults() {
        root.barWidgetIconName = defaults.barWidgetIconName || "device-tv"
        root.barWidgetText = defaults.barWidgetText || "AnimeReloaded"
        root.barWidgetIconColor = _normaliseIconColorKey(defaults.barWidgetIconColor || "primary")
        root.episodeDownloadPath = ""
    }

    spacing: Style.marginL

    NLabel {
        label: "Bar Widget"
        description: "Customize the bar button icon, label, and icon color."
    }

    RowLayout {
        spacing: Style.marginM

        Rectangle {
            Layout.preferredWidth: Math.max(160, previewRow.implicitWidth + Style.marginM * 2)
            Layout.preferredHeight: 42
            radius: Style.radiusL
            color: Style.capsuleColor
            border.color: Style.capsuleBorderColor
            border.width: Style.capsuleBorderWidth

            RowLayout {
                id: previewRow
                anchors.centerIn: parent
                spacing: Style.marginXS

                NIcon {
                    icon: root.barWidgetIconName
                    color: Color.resolveColorKey(root.barWidgetIconColor)
                }

                NText {
                    visible: root.barWidgetText.length > 0
                    text: root.barWidgetText
                    color: Color.mOnSurface
                }
            }
        }

        NButton {
            text: "Choose Icon"
            onClicked: iconPicker.open()
        }
    }

    NIconPicker {
        id: iconPicker
        initialIcon: root.barWidgetIconName
        onIconSelected: function(iconName) {
            root.barWidgetIconName = iconName
        }
    }

    NTextInput {
        Layout.fillWidth: true
        label: "Button Text"
        description: "Text shown next to the icon in the bar. Leave it empty for an icon-only button."
        placeholderText: "AnimeReloaded"
        text: root.barWidgetText
        onTextChanged: root.barWidgetText = text
    }

    NLabel {
        label: "Icon Color"
        description: "Choose one of the five theme colors for the bar icon."
    }

    Flow {
        Layout.fillWidth: true
        spacing: Style.marginS

        Repeater {
            model: root.colorOptions

            delegate: Item {
                required property var modelData

                readonly property color swatchColor: Color.resolveColorKey(modelData.key)
                readonly property bool selected: root.barWidgetIconColor === modelData.key
                readonly property bool hovered: hover.hovered

                implicitWidth: chipRow.implicitWidth + 24
                implicitHeight: 36
                opacity: enabled ? 1 : 0.45
                scale: mouseArea.pressed ? 0.985 : 1.0

                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: selected
                        ? Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.96)
                        : (hovered
                            ? Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.9)
                            : Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.78))
                    border.width: 1
                    border.color: selected
                        ? swatchColor
                        : (hovered
                            ? Qt.rgba(swatchColor.r, swatchColor.g, swatchColor.b, 0.44)
                            : Qt.rgba(swatchColor.r, swatchColor.g, swatchColor.b, 0.24))

                    Behavior on color { ColorAnimation { duration: 140 } }
                    Behavior on border.color { ColorAnimation { duration: 140 } }
                }

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 8

                    Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        color: swatchColor
                        border.width: selected ? 0 : 1
                        border.color: Qt.rgba(Color.mOnSurface.r, Color.mOnSurface.g, Color.mOnSurface.b, 0.14)

                        Text {
                            anchors.centerIn: parent
                            visible: selected
                            text: "✓"
                            font.pixelSize: 8
                            font.bold: true
                            color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.95)
                        }
                    }

                    Text {
                        text: modelData.name
                        font.pixelSize: 12
                        font.bold: selected
                        color: Color.mOnSurface
                    }
                }

                HoverHandler { id: hover }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.barWidgetIconColor = modelData.key
                }
            }
        }
    }

    NText {
        Layout.fillWidth: true
        text: "Selected: " + root._colorOptionName(root.barWidgetIconColor)
            + " (" + root._colorHex(Color.resolveColorKey(root.barWidgetIconColor)) + ")"
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
    }

    NLabel {
        label: "Episode Downloads"
        description: "Choose where downloaded episodes will be saved. Leave it empty to use the default AnimeReloaded downloads folder."
    }

    NTextInput {
        Layout.fillWidth: true
        label: "Download Folder"
        description: "Custom folder for episode downloads."
        placeholderText: root.defaultEpisodeDownloadPath
        text: root.episodeDownloadPath
        onTextChanged: root.episodeDownloadPath = text
    }

    NText {
        Layout.fillWidth: true
        text: "Current location: " + root.effectiveEpisodeDownloadPath
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
        wrapMode: Text.Wrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NButton {
            text: "Choose Folder"
            onClicked: downloadFolderPicker.openFilePicker()
        }

        NButton {
            text: "Use Default"
            visible: root._normaliseDirectoryPath(root.episodeDownloadPath).length > 0
            onClicked: root.episodeDownloadPath = ""
        }

        Item {
            Layout.fillWidth: true
        }
    }

    NFilePicker {
        id: downloadFolderPicker
        title: "Select episode download folder"
        initialPath: root.effectiveEpisodeDownloadPath
        selectionMode: "folders"

        onAccepted: function(paths) {
            if (paths.length > 0)
                root.episodeDownloadPath = root._normaliseDirectoryPath(paths[0])
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Item {
            Layout.fillWidth: true
        }

        NButton {
            text: "Reset to Defaults"
            icon: "refresh"
            onClicked: root.resetToDefaults()
        }
    }

    function saveSettings() {
        if (!pluginApi) {
            Logger.e("AnimeReloaded", "Cannot save settings: pluginApi is null")
            return
        }

        pluginApi.pluginSettings.barWidgetIconName = root.barWidgetIconName
        pluginApi.pluginSettings.barWidgetText = root.barWidgetText
        pluginApi.pluginSettings.barWidgetIconColor = root._normaliseIconColorKey(root.barWidgetIconColor)
        pluginApi.pluginSettings.episodeDownloadPath = root._normaliseDirectoryPath(root.episodeDownloadPath)
        pluginApi.saveSettings()
    }
}
