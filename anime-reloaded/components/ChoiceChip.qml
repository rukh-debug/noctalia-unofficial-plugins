import QtQuick
import qs.Commons

Item {
    id: root

    property string text: ""
    property bool selected: false
    property bool enabled: true
    property real minWidth: 0
    property real horizontalPadding: 14
    property real controlHeight: 32
    property real fontPixelSize: 11
    property real letterSpacing: 0.0
    property bool boldWhenSelected: true
    property color accentColor: Color.mPrimary
    property color selectedTextColor: Color.mOnPrimary
    property color hoverTextColor: accentColor
    property color idleTextColor: Color.mOnSurfaceVariant
    property color idleBackgroundColor: Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.82)
    property color hoverBackgroundColor: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.18)
    property color selectedBackgroundColor: accentColor
    property color idleBorderColor: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.28)
    property color hoverBorderColor: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.45)
    property color selectedBorderColor: accentColor

    signal clicked()

    readonly property bool hovered: enabled && hover.hovered
    readonly property bool pressed: enabled && area.pressed

    implicitWidth: Math.max(minWidth, label.implicitWidth + horizontalPadding * 2)
    implicitHeight: controlHeight
    opacity: enabled ? 1 : 0.45
    scale: pressed ? 0.985 : 1.0

    Behavior on opacity { NumberAnimation { duration: 160 } }
    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.selected
            ? root.selectedBackgroundColor
            : (root.hovered ? root.hoverBackgroundColor : root.idleBackgroundColor)
        border.width: 1
        border.color: root.selected
            ? root.selectedBorderColor
            : (root.hovered ? root.hoverBorderColor : root.idleBorderColor)
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        font.pixelSize: root.fontPixelSize
        font.bold: root.boldWhenSelected && root.selected
        font.letterSpacing: root.letterSpacing
        color: root.selected
            ? root.selectedTextColor
            : (root.hovered ? root.hoverTextColor : root.idleTextColor)
        Behavior on color { ColorAnimation { duration: 160 } }
    }

    HoverHandler { id: hover }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
