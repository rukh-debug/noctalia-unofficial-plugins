import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets

Popup {
  id: root
  padding: Style.marginXXS
  modal: false
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  
  // Props
  property var availableModels: []
  property string currentModel: ""
  property bool fetchingModels: false
  property string modelsError: ""
  
  // Signals
  signal modelSelected(string model)
  
  background: Rectangle {
    color: Color.mSurface
    border.color: Color.mPrimary
    border.width: 1
    radius: Style.radiusS
  }
  
  contentItem: ColumnLayout {
    spacing: Style.marginXXS
    
    // Header
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS
      
      NText {
        text: "Select Model"
        font.pointSize: Style.fontSizeS
        font.weight: Font.Medium
        color: Color.mOnSurface
        Layout.fillWidth: true
      }
      
      NIcon {
        icon: "x"
        pointSize: Style.fontSizeS
        color: closeButtonMouse.containsMouse ? Color.mOnSurface : Color.mOnSurfaceVariant
        
        MouseArea {
          id: closeButtonMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.close()
        }
      }
    }
    
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 1
      color: Style.capsuleBorderColor
    }
    
    // Model list
    ListView {
      id: modelListView
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(contentHeight, 300)
      clip: true
      model: availableModels.length > 0 ? availableModels : [currentModel || "No models available"]
      currentIndex: {
        if (availableModels.length === 0) return 0;
        var idx = availableModels.indexOf(currentModel);
        return idx >= 0 ? idx : 0;
      }
      
      delegate: ItemDelegate {
        width: modelListView.width
        
        contentItem: RowLayout {
          spacing: Style.marginS
          
          NIcon {
            icon: "robot"
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
          }
          
          NText {
            text: modelData
            color: Color.mOnSurface
            font.pointSize: Style.fontSizeS
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
          
          NIcon {
            icon: "check"
            pointSize: Style.fontSizeS
            color: Color.mPrimary
            visible: modelData === currentModel
          }
        }
        
        highlighted: ListView.isCurrentItem
        
        background: Rectangle {
          color: parent.hovered ? Color.mHover : "transparent"
          radius: Style.radiusS
        }
        
        onClicked: {
          if (availableModels.length > 0) {
            root.modelSelected(modelData);
            root.close();
          }
        }
      }
      
      ScrollIndicator.vertical: ScrollIndicator { }
    }
    
    // Loading/Error state
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginXXS
      visible: modelsError || fetchingModels
      
      NIcon {
        icon: modelsError ? "alert-circle" : "loader-2"
        pointSize: Style.fontSizeXS
        color: modelsError ? Color.mOnSurfaceVariant : Color.mPrimary
        
        RotationAnimation on rotation {
          running: fetchingModels
          loops: Animation.Infinite
          from: 0
          to: 360
          duration: 1000
        }
      }
      
      NText {
        text: modelsError ? modelsError : "Loading models..."
        font.pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        Layout.fillWidth: true
      }
    }
  }
}
