import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

NIconButton {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property bool wasGenerating: false

  readonly property var mainInstance: pluginApi && pluginApi.mainInstance
  readonly property bool isGenerating: mainInstance && mainInstance.isGenerating || false

  baseSize: Style.getCapsuleHeightForScreen(screen ? screen.name : "")
  applyUiScale: false
  customRadius: Style.radiusL

  icon: root.isGenerating ? "loader-2" : "sparkles"

  colorBg: Style.capsuleColor
  colorFg: Color.mPrimary
  colorBorder: Style.capsuleBorderColor
  border.width: Style.capsuleBorderWidth

  tooltipText: root.isGenerating ? "Generating..." : "Open OpenWebUI"

  onClicked: {
    if (pluginApi) {
      pluginApi.openPanel(screen)
    }
  }

  RotationAnimation on rotation {
    from: 0
    to: 360
    duration: 1000
    loops: Animation.Infinite
    running: root.isGenerating
  }

  onIsGeneratingChanged: {
    if (!isGenerating) {
      rotation = 0
    }

    wasGenerating = isGenerating
  }

  onRightClicked: {
      PanelService.showContextMenu(contextMenu, root, screen);
  }
}
