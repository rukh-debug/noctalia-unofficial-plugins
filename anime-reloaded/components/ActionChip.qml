import QtQuick
import qs.Commons

Item {
    id: root

    property string text: ""
    property string leadingText: ""
    property bool enabled: true
    property bool active: false
    property real minWidth: 0
    property real horizontalPadding: 14
    property real controlHeight: 32
    property real gap: 6
    property real fontPixelSize: 10
    property real letterSpacing: 0.4
    property bool boldLabel: true
    property real disabledOpacity: 0.45

    function _themeColor(name, fallback) {
        var value = Color ? Color[name] : null
        return value !== undefined && value !== null ? value : fallback
    }

    property color baseColor: Color.mSurface
    property color hoverColor: _themeColor("mPrimaryContainer",
        Qt.tint(Color.mSurface, Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.18)))
    property color activeColor: Color.mPrimary
    property color activeHoverColor: activeColor

    property color baseBorderColor: _themeColor("mOutlineVariant",
        _themeColor("mOutline", Color.mOnSurfaceVariant))
    property color hoverBorderColor: Color.mPrimary
    property color activeBorderColor: Color.mPrimary
    property color activeHoverBorderColor: activeBorderColor

    property color baseTextColor: Color.mOnSurfaceVariant
    property color hoverTextColor: _themeColor("mOnPrimaryContainer", Color.mPrimary)
    property color activeTextColor: Color.mOnPrimary
    property color activeHoverTextColor: activeTextColor

    signal clicked()

    readonly property bool hovered: enabled && hover.hovered
    readonly property bool pressed: enabled && area.pressed

    function _backgroundColor() {
        if (active)
            return hovered ? activeHoverColor : activeColor
        return hovered ? hoverColor : baseColor
    }

    function _borderColor() {
        if (active)
            return hovered ? activeHoverBorderColor : activeBorderColor
        return hovered ? hoverBorderColor : baseBorderColor
    }

    function _textColor() {
        if (active)
            return hovered ? activeHoverTextColor : activeTextColor
        return hovered ? hoverTextColor : baseTextColor
    }

    implicitWidth: Math.max(minWidth, contentRow.implicitWidth + horizontalPadding * 2)
    implicitHeight: controlHeight
    opacity: enabled ? 1 : disabledOpacity
    scale: pressed ? 0.985 : 1.0

    Behavior on opacity { NumberAnimation { duration: 160 } }
    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root._backgroundColor()
        border.width: 1
        border.color: root._borderColor()
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on border.color { ColorAnimation { duration: 160 } }
    }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: root.leadingText.length > 0 ? root.gap : 0

        Text {
            visible: root.leadingText.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.leadingText
            font.pixelSize: root.fontPixelSize
            font.bold: true
            color: root._textColor()
            Behavior on color { ColorAnimation { duration: 160 } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.pixelSize: root.fontPixelSize
            font.bold: root.boldLabel
            font.letterSpacing: root.letterSpacing
            color: root._textColor()
            Behavior on color { ColorAnimation { duration: 160 } }
        }
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
