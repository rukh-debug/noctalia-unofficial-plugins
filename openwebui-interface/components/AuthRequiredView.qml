import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  anchors.centerIn: parent
  width: parent.width - (Style.marginL * 2)
  spacing: Style.marginL

  NIcon {
    icon: "shield-lock"
    pointSize: 64
    color: Color.mOnSurfaceVariant
    Layout.alignment: Qt.AlignHCenter
  }

  NText {
    text: "Authentication Required"
    font.pointSize: Style.fontSizeXXL
    font.weight: Font.Bold
    Layout.alignment: Qt.AlignHCenter
    color: Color.mOnSurface
  }

  NText {
    text: "You are not authenticated. Please authenticate to your OpenWebUI account from the plugin settings."
    font.pointSize: Style.fontSizeM
    color: Color.mOnSurfaceVariant
    wrapMode: Text.Wrap
    horizontalAlignment: Text.AlignHCenter
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignHCenter
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: 2
    color: Style.capsuleBorderColor
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NText {
      text: "How to authenticate:"
      font.pointSize: Style.fontSizeM
      font.weight: Font.Medium
      color: Color.mOnSurface
      Layout.alignment: Qt.AlignHCenter
    }

    NText {
      text: "1. Open Noctalia Settings"
      font.pointSize: Style.fontSizeS
      color: Color.mOnSurfaceVariant
      Layout.fillWidth: true
    }

    NText {
      text: "2. Go to Plugins → OpenWebUI Launcher"
      font.pointSize: Style.fontSizeS
      color: Color.mOnSurfaceVariant
      Layout.fillWidth: true
    }

    NText {
      text: "3. Enter your credentials or API key"
      font.pointSize: Style.fontSizeS
      color: Color.mOnSurfaceVariant
      Layout.fillWidth: true
    }

    NText {
      text: "4. Save settings and return here"
      font.pointSize: Style.fontSizeS
      color: Color.mOnSurfaceVariant
      Layout.fillWidth: true
    }
  }
}
