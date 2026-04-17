import QtQuick
import qs.Commons

Item {
    id: root

    property string text: ""
    property bool enabled: true
    property bool selected: false
    property real buttonSize: 38
    property real innerSize: 32
    property real iconPixelSize: 16
    property real idleOpacity: 1.0
    property real activeOpacity: 1.0

    signal clicked()

    function _themeColor(name, fallback) {
        var value = Color ? Color[name] : null
        return value !== undefined && value !== null ? value : fallback
    }

    readonly property bool hovered: enabled && hover.hovered
    readonly property bool pressed: enabled && area.pressed

    implicitWidth: buttonSize
    implicitHeight: buttonSize
    opacity: enabled ? 1 : 0.45
    scale: pressed ? 0.97 : 1.0

    Behavior on opacity { NumberAnimation { duration: 160 } }
    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.centerIn: parent
        width: root.innerSize
        height: root.innerSize
        radius: width / 2
        color: (root.selected || root.hovered)
            ? _themeColor("mPrimaryContainer",
                Qt.tint(Color.mSurface, Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.22)))
            : "transparent"
        border.width: root.selected || root.hovered ? 1 : 0
        border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.25)
        scale: root.hovered ? 1.06 : 1.0
        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.width { NumberAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    Text {
        anchors.centerIn: parent
        text: root.text
        font.pixelSize: root.iconPixelSize
        color: (root.selected || root.hovered)
            ? _themeColor("mOnPrimaryContainer", Color.mPrimary)
            : Color.mOnSurfaceVariant
        opacity: (root.selected || root.hovered) ? root.activeOpacity : root.idleOpacity
        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on opacity { NumberAnimation { duration: 180 } }
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
