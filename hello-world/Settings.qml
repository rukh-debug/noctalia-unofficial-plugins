import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Settings UI Component for Hello World Plugin
ColumnLayout {
  id: root

  // Plugin API (injected by the settings dialog system)
  property var pluginApi: null

  // Local state - track changes before saving
  property string valueMessage: pluginApi?.pluginSettings?.message || pluginApi?.manifest?.metadata?.defaultSettings?.message || ""
  property color valueBgColor: pluginApi?.pluginSettings?.backgroundColor || pluginApi?.manifest?.metadata?.defaultSettings?.backgroundColor || "transparent"

  spacing: Style.marginM

  Component.onCompleted: {
    Logger.i("HelloWorld", "Settings UI loaded");
  }

  NTextInput {
    Layout.fillWidth: true
    label: "Message"
    description: "Custom message to display in the bar widget and panel"
    placeholderText: "Enter a message..."
    text: root.valueMessage
    onTextChanged: root.valueMessage = text
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel {
      label: "Background Color"
      description: "Background color for the bar widget"
    }

    NColorPicker {
      Layout.preferredWidth: Style.sliderWidth
      Layout.preferredHeight: Style.baseWidgetSize
      selectedColor: root.valueBgColor
      onColorSelected: function (color) {
        root.valueBgColor = color;
      }
    }
  }

  // This function is called by the dialog to save settings
  function saveSettings() {
    if (!pluginApi) {
      Logger.e("HelloWorld", "Cannot save settings: pluginApi is null");
      return;
    }

    // Update the plugin settings object
    pluginApi.pluginSettings.message = root.valueMessage;
    pluginApi.pluginSettings.backgroundColor = root.valueBgColor.toString();

    // Save to disk
    pluginApi.saveSettings();

    Logger.i("HelloWorld", "Settings saved successfully");
  }
}
