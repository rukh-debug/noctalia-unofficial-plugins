import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Rectangle {
  id: root

  property bool visibleAction: false
  property string actionLabel: "Refetch page"
  property string actionIcon: "refresh"
  signal triggered()

  visible: visibleAction
  radius: Style.radiusS
  color: Qt.alpha(Color.mSurface, 0.9)
  border.width: 1
  border.color: Qt.alpha(Style.capsuleBorderColor, 0.7)
  implicitWidth: actionRow.implicitWidth + Style.marginS * 2
  implicitHeight: actionRow.implicitHeight + Style.marginXS * 2

  RowLayout {
    id: actionRow
    anchors.centerIn: parent
    spacing: Style.marginXS

    NIcon {
      icon: root.actionIcon
      pointSize: Style.fontSizeXS
      color: Color.mPrimary
    }

    NText {
      text: root.actionLabel
      pointSize: Style.fontSizeXS
      color: Color.mOnSurface
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.color = Qt.alpha(Color.mHover, 0.82)
    onExited: root.color = Qt.alpha(Color.mSurface, 0.9)
    onClicked: root.triggered()
  }
}
