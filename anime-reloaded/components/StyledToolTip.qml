import QtQuick
import qs.Commons

Item {
    id: root

    property Item target: null
    property string text: ""
    property real offset: 8
    property bool above: false
    property bool shown: false

    z: 100
    width: bubble.implicitWidth
    height: bubble.implicitHeight
    visible: opacity > 0
    opacity: shown ? 1 : 0
    scale: shown ? 1.0 : 0.96

    x: {
        if (!target || !parent)
            return 0
        var point = target.mapToItem(parent, target.width / 2, target.height / 2)
        var desired = point.x - width / 2
        return Math.max(0, Math.min(parent.width - width, desired))
    }

    y: {
        if (!target || !parent)
            return 0
        var point = target.mapToItem(parent, target.width / 2, target.height / 2)
        var desired = above
            ? point.y - (target.height / 2) - height - offset
            : point.y + (target.height / 2) + offset
        return Math.max(0, Math.min(parent.height - height, desired))
    }

    Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

    Rectangle {
        id: bubble
        implicitWidth: label.implicitWidth + 18
        implicitHeight: label.implicitHeight + 10
        anchors.fill: parent
        radius: 9
        color: Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.97)
        border.width: 1
        border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.28)
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: Color.mOnSurface
        font.pixelSize: 10
        font.letterSpacing: 0.2
        wrapMode: Text.NoWrap
    }
}
