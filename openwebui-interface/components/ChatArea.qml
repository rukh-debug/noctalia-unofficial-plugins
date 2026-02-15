import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
    id: root
    
    property var messages: []
    property string currentChatId: ""
    property bool isGenerating: false
    property bool loadingChat: false
    property string currentResponse: ""
    property var pluginApi
    
    // Messages container
    Rectangle {
        anchors.fill: parent
        color: Color.mSurface
        radius: Style.radiusM
        clip: true
        
        // Loading overlay when loading a chat
        Rectangle {
            anchors.fill: parent
            color: Color.mSurface
            visible: root.loadingChat
            z: 10
            
            ColumnLayout {
                anchors.centerIn: parent
                spacing: Style.marginM
                
                NIcon {
                    Layout.alignment: Qt.AlignHCenter
                    icon: "loader-2"
                    color: Color.mPrimary
                    pointSize: Style.fontSizeXXL * 2
                    
                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                        running: root.loadingChat
                    }
                }
                
                NText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Loading chat..."
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeM
                    font.weight: Font.Medium
                }
            }
        }

        // Empty state
        Item {
            anchors.fill: parent
            visible: root.messages.length === 0 && !root.isGenerating && !root.loadingChat

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Style.marginM

                NIcon {
                    Layout.alignment: Qt.AlignHCenter
                    icon: "message-circle"
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeXXL * 2
                }

                NText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.currentChatId === "" ? "Start a conversation" : "No messages yet"
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeM
                    font.weight: Font.Medium
                }

                NText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Type a message below to begin"
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeS
                }
            }
        }
    }
    
    // Chat messages using Flickable + Column + Repeater pattern
    Flickable {
        id: chatFlickable
        anchors.fill: parent
        anchors.margins: Style.marginS
        contentWidth: width
        contentHeight: messageColumn.height
        clip: true
        visible: root.messages.length > 0 || root.isGenerating
        boundsBehavior: Flickable.StopAtBounds

        property real wheelScrollMultiplier: 4.0

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 8;
                const newY = chatFlickable.contentY - (delta * chatFlickable.wheelScrollMultiplier);
                chatFlickable.contentY = Math.max(0, Math.min(newY, chatFlickable.contentHeight - chatFlickable.height));
                chatFlickable.autoScrollEnabled = chatFlickable.isNearBottom;
                event.accepted = true;
            }
        }

        // Auto-scroll state
        property bool autoScrollEnabled: true

        // Check if we're near the bottom (with threshold)
        readonly property bool isNearBottom: {
            if (contentHeight <= height)
                return true;
            return contentY >= contentHeight - height - 30;
        }

        // Smoothly scroll to bottom
        function scrollToBottom() {
            if (contentHeight > height) {
                contentY = contentHeight - height;
            }
        }

        // Handle content height changes - scroll to bottom if auto-scroll enabled
        onContentHeightChanged: {
            if (autoScrollEnabled && contentHeight > height) {
                scrollToBottom();
            }
        }

        // Detect manual scrolling - disable auto-scroll if user scrolls up
        onMovementEnded: {
            autoScrollEnabled = isNearBottom;
        }

        onFlickEnded: {
            autoScrollEnabled = isNearBottom;
        }

        // Messages column
        Column {
            id: messageColumn
            width: chatFlickable.width
            spacing: Style.marginM

            // Existing messages from history
            Repeater {
                id: messageRepeater
                model: root.messages

                MessageBubble {
                    width: parent.width
                    message: modelData
                    pluginApi: root.pluginApi

                    onCopyRequested: function (text) {
                       Quickshell.clipboardText = text;
                       ToastService.showNotice("Copied to clipboard");
                    }
                }
            }

            // Streaming message (shown during generation)
            MessageBubble {
                id: streamingBubble
                width: parent.width
                
                visible: root.isGenerating && root.currentResponse.trim() !== ""
                pluginApi: root.pluginApi
                message: ({
                    "id": "streaming",
                    "role": "assistant",
                    "content": root.currentResponse,
                    "isStreaming": true
                })
            }
        }
    }

    // Scroll to bottom button - only visible when user has scrolled away
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.marginM
        width: 32
        height: 32
        radius: width / 2
        color: Color.mPrimary
        visible: !chatFlickable.autoScrollEnabled && (root.messages.length > 0 || root.isGenerating)
        opacity: scrollButtonMouse.containsMouse ? 1.0 : 0.8

        Behavior on opacity {
            NumberAnimation {
                duration: Style.animationFast
            }
        }

        NIcon {
            anchors.centerIn: parent
            icon: "chevron-down"
            color: Color.mOnPrimary
            pointSize: Style.fontSizeM
        }

        MouseArea {
            id: scrollButtonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                chatFlickable.autoScrollEnabled = true;
                chatFlickable.scrollToBottom();
            }
        }
    }
}
