import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets

Item {
    id: root
    property var message
    property var pluginApi

    readonly property int bubblePadding: Style.marginM

    signal copyRequested(string text)

    implicitHeight: mainLayout.implicitHeight
    implicitWidth: parent ? parent.width : 400

    property bool isHovered: false

    RowLayout {
        id: mainLayout
        anchors.fill: parent
        spacing: Style.marginS

        // Assistant Avatar - OpenWebUI icon (theme-aware)
        Item {
            Layout.alignment: Qt.AlignTop
            visible: message.role === "assistant"
            implicitWidth: 32
            implicitHeight: 32
            
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
                sourceSize.width: 32
                sourceSize.height: 32
                fillMode: Image.PreserveAspectFit
                smooth: true
                antialiasing: true
                mipmap: true
            }
        }

        // Spacer for User message (pushes bubble to right)
        Item {
            visible: message.role === "user"
            Layout.fillWidth: true
        }

        // Message Bubble
        Rectangle {
            id: bubbleRect

            Layout.maximumWidth: root.width * 0.8
            Layout.preferredWidth: Math.min(Layout.maximumWidth, contentCol.implicitWidth + (root.bubblePadding * 2))
            Layout.preferredHeight: contentCol.implicitHeight + (root.bubblePadding * 2)

            color: message.role === "user" ? Color.mSurfaceVariant : Color.mSurface
            radius: Style.radiusM
            
            // Border for assistant message to distinguish from background if needed
            border.color: message.role === "assistant" ? Style.capsuleBorderColor : "transparent"
            border.width: message.role === "assistant" ? 1 : 0

            // Hover detection
            MouseArea {
                id: bubbleHoverArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onContainsMouseChanged: root.isHovered = containsMouse
            }

            // Sharp Corner Hack for User (Top Right)
            Rectangle {
                visible: message.role === "user"
                anchors.top: parent.top
                anchors.right: parent.right
                width: parent.radius
                height: parent.radius
                color: parent.color
            }

            // Sharp Corner Hack for Assistant (Top Left)
            Rectangle {
                visible: message.role === "assistant"
                anchors.top: parent.top
                anchors.left: parent.left
                width: parent.radius
                height: parent.radius
                color: parent.color
            }

            // Copy Button (Inside Bubble - Bottom Right)
            Rectangle {
                id: copyButton
                visible: !message.isStreaming
                width: 28
                height: 28
                radius: 6
                
                // Always position in bottom-right corner
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.bottomMargin: Style.marginS
                anchors.rightMargin: Style.marginS
                
                color: copyButtonMouse.containsMouse ? Color.mSurfaceVariant : "transparent"
                
                z: 10

                NIcon {
                    anchors.centerIn: parent
                    icon: "copy"
                    pointSize: Style.fontSizeS
                    color: copyButtonMouse.containsMouse ? Color.mPrimary : Color.mOnSurfaceVariant
                    opacity: copyButtonMouse.containsMouse ? 1.0 : 0.3
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.InOutQuad }
                    }
                }

                MouseArea {
                    id: copyButtonMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copyRequested(message.content)
                    onContainsMouseChanged: {
                        if (containsMouse) root.isHovered = true
                    }
                    ToolTip.visible: containsMouse
                    ToolTip.text: "Copy"
                }
            }

            ColumnLayout {
                id: contentCol
                anchors.centerIn: parent
                width: parent.width - (root.bubblePadding * 2)
                spacing: Style.marginS

                TextEdit {
                    Layout.fillWidth: true
                    wrapMode: TextEdit.Wrap
                    readOnly: true
                    selectByMouse: true
                    
                    text: message.content
                    textFormat: message.role === "assistant" ? Text.MarkdownText : Text.PlainText
                    
                    color: Color.mOnSurface
                    font.pointSize: Style.fontSizeM
                    
                    selectionColor: Color.mPrimary
                    selectedTextColor: Color.mOnPrimary
                    
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }

                // Streaming indicator
                RowLayout {
                    visible: message.isStreaming || false
                    spacing: Style.marginXS

                    NIcon {
                        icon: "loader-2"
                        color: Color.mPrimary
                        pointSize: Style.fontSizeXS

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 1000
                            loops: Animation.Infinite
                            running: message.isStreaming || false
                        }
                    }

                    NText {
                        text: "Generating..."
                        color: Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeXS
                    }
                }
            }
        }

        // Spacer for Assistant message (pushes bubble to left)
        Item {
            visible: message.role === "assistant"
            Layout.fillWidth: true
        }
    }
}
