import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

RowLayout {
  id: root
  spacing: Style.marginM
  Layout.margins: Style.marginM
  
  // Props from parent
  property bool sidebarVisible
  property string currentModel
  property string defaultModel
  property var pluginApi
  
  // Model selector state
  property var availableModels: []
  property bool fetchingModels: false
  property string modelsError: ""
  property var chatData: null
  
  // Signals
  signal sidebarToggled()
  signal modelChanged(string model)
  signal setDefaultModel(string model)
  signal openModelSelector()
  
  NIconButton {
    icon: sidebarVisible ? "layout-sidebar-left-collapse" : "layout-sidebar-left-expand"
    tooltipText: sidebarVisible ? "Hide sidebar" : "Show sidebar"
    onClicked: root.sidebarToggled()
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginXXS
    
    // Current model display
    NText {
      text: currentModel
      font.pointSize: Style.fontSizeS
      color: Color.mOnSurfaceVariant
      elide: Text.ElideRight
      Layout.fillWidth: true
    }
    
    // Buttons row
    RowLayout {
      spacing: Style.marginXXS
      Layout.alignment: Qt.AlignTop
      
      // Change model button
      Rectangle {
        id: changeModelButton
        implicitWidth: changeModelButtonContent.implicitWidth + Style.marginM
        implicitHeight: changeModelButtonContent.implicitHeight + Style.marginS
        color: changeModelButtonMouse.containsMouse ? Color.mPrimary : Color.mSurfaceVariant
        radius: Style.radiusS
        
        RowLayout {
          id: changeModelButtonContent
          anchors.centerIn: parent
          spacing: Style.marginXXS
          
          NIcon {
            icon: "edit"
            pointSize: Style.fontSizeXS
            color: changeModelButtonMouse.containsMouse ? Color.mOnPrimary : Color.mOnSurface
          }
          
          NText {
            text: "Change"
            font.pointSize: Style.fontSizeXS
            color: changeModelButtonMouse.containsMouse ? Color.mOnPrimary : Color.mOnSurface
          }
        }
        
        MouseArea {
          id: changeModelButtonMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openModelSelector()
        }
      }
      
      // Set default button (shown when current model differs from default)
      Rectangle {
        implicitWidth: setDefaultButtonContent.implicitWidth + Style.marginM
        implicitHeight: setDefaultButtonContent.implicitHeight + Style.marginS
        visible: currentModel && defaultModel && currentModel !== defaultModel
        color: setDefaultButtonMouse.containsMouse ? Color.mPrimary : Color.mSurfaceVariant
        radius: Style.radiusS
        opacity: 0.7
        
        RowLayout {
          id: setDefaultButtonContent
          anchors.centerIn: parent
          spacing: Style.marginXXS
          
          NIcon {
            icon: "star"
            pointSize: Style.fontSizeXS
            color: setDefaultButtonMouse.containsMouse ? Color.mOnPrimary : Color.mOnSurface
          }
          
          NText {
            text: "Set default"
            font.pointSize: Style.fontSizeXS
            color: setDefaultButtonMouse.containsMouse ? Color.mOnPrimary : Color.mOnSurface
          }
        }
        
        MouseArea {
          id: setDefaultButtonMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.setDefaultModel(currentModel)
        }
      }
    }
  }
  
  // Chat title in top right
  RowLayout {
    spacing: Style.marginS
    Layout.alignment: Qt.AlignTop
    
    Item {
      implicitWidth: Style.fontSizeM * 1.5
      implicitHeight: Style.fontSizeM * 1.5
      
      // Detect theme by checking if surface color is dark or light
      readonly property bool isDarkTheme: {
        var r = Color.mSurface.r;
        var g = Color.mSurface.g;
        var b = Color.mSurface.b;
        var brightness = (r * 299 + g * 587 + b * 114) / 1000;
        return brightness < 0.5;
      }
      
      Image {
        anchors.fill: parent
        source: parent.isDarkTheme ? "../assets/openwebui-light.svg" : "../assets/openwebui-dark.svg"
        sourceSize.height: Style.fontSizeM * 1.5
        sourceSize.width: Style.fontSizeM * 1.5
        fillMode: Image.PreserveAspectFit
        smooth: true
        antialiasing: true
        mipmap: true
      }
    }
    
    NText {
      text: {
        var t = chatData ? (chatData.title || "Untitled Chat") : "OpenWebUI";
        return t.length > 20 ? t.substring(0, 20) + "..." : t;
      }
      font.pointSize: Style.fontSizeM
      font.weight: Font.Medium
      color: Color.mOnSurface
      elide: Text.ElideRight
      Layout.maximumWidth: 250
      Layout.alignment: Qt.AlignVCenter
      wrapMode: Text.NoWrap
    }
  }
}
