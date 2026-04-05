import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets

NIconButton {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property bool isLoading: (mainInstance?.isLoadingSearch || false) || (mainInstance?.isLoadingChapters || false) || (mainInstance?.isLoadingPages || false)
  readonly property bool isAuthed: mainInstance?.isAuthenticated || false

  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

  baseSize: capsuleHeight
  applyUiScale: false
  customRadius: Style.radiusL

  icon: isLoading ? "loader-2" : "book-2"
  tooltipText: isAuthed ? "Open MangaDex Reader (authenticated)" : "Open MangaDex Reader"

  colorBg: Style.capsuleColor
  colorFg: isAuthed ? Color.mPrimary : Color.mOnSurface
  colorBorder: Style.capsuleBorderColor
  border.width: Style.capsuleBorderWidth

  RotationAnimation on rotation {
    from: 0
    to: 360
    duration: 1000
    loops: Animation.Infinite
    running: root.isLoading
  }

  onClicked: {
    if (pluginApi) {
      pluginApi.openPanel(screen);
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": "Open Reader",
        "action": "open-reader",
        "icon": "book-2"
      },
      {
        "label": "Search...",
        "action": "search",
        "icon": "search"
      }
    ]

    onTriggered: function(action) {
      contextMenu.close();
      PanelService.closeContextMenu(screen);

      if (action === "open-reader") {
        if (pluginApi) {
          pluginApi.openPanel(screen);
        }
      } else if (action === "search") {
        if (pluginApi) {
          pluginApi.openPanel(screen);
        }
      }
    }
  }

  onRightClicked: {
    PanelService.showContextMenu(contextMenu, root, screen);
  }
}