import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    // Plugin API (injected by the settings dialog system)
    property var pluginApi: null

    // Local state
    property color editTextColor:
        pluginApi?.pluginSettings?.textColor ||
        pluginApi?.manifest?.metadata?.defaultSettings?.textColor ||
        "#f4d24f"
    property int editMaxTextLength:
        pluginApi?.pluginSettings?.maxTextLength ??
        pluginApi?.manifest?.metadata?.defaultSettings?.maxTextLength ??
        30

    spacing: Style.marginM

    NLabel {
        label: "Appearance"
        description: "Customize how the keymode text is shown"
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NLabel {
            label: "Text Color"
            description: "Choose a custom color for the keymode text"
        }

        NColorPicker {
            Layout.preferredWidth: Style.sliderWidth
            Layout.preferredHeight: Style.baseWidgetSize
            selectedColor: root.editTextColor
            onColorSelected: function(color) {
                root.editTextColor = color
            }
        }
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        Layout.bottomMargin: Style.marginS
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NLabel {
            label: "Max Text Length"
            description: "Maximum characters to display (0 = no limit)"
        }

        NSpinBox {
            from: 0
            to: 200
            value: root.editMaxTextLength
            onValueChanged: root.editMaxTextLength = value
        }
    }

    function saveSettings() {
        if (!pluginApi) {
            Logger.e("mangowc-keymode-submap", "Cannot save: pluginApi is null")
            return
        }

        pluginApi.pluginSettings.textColor = root.editTextColor.toString()
        pluginApi.pluginSettings.maxTextLength = root.editMaxTextLength
        pluginApi.saveSettings()
    }
}
