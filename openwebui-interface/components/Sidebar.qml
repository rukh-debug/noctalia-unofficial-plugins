import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets

Rectangle {
    id: root
    
    property var chatList: []
    property string currentChatId: ""
    property bool fetchingChats: false
    property string chatsError: ""
    
    signal chatSelected(string chatId)
    signal newChatRequested()
    signal refreshRequested()
    signal loadMoreRequested()
    
    color: Color.mSurfaceVariant
    clip: true
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginS
        
        // Sidebar header
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            
            NText {
                text: "Chats"
                font.pointSize: Style.fontSizeL
                font.weight: Font.Bold
                color: Color.mOnSurface
                Layout.fillWidth: true
            }
            
            NIconButton {
                icon: "refresh"
                tooltipText: "Refresh chats"
                enabled: !root.fetchingChats
                onClicked: root.refreshRequested()
                
                RotationAnimation on rotation {
                    running: root.fetchingChats
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 1000
                }
            }
            
            NIconButton {
                icon: "plus"
                tooltipText: "New chat"
                onClicked: root.newChatRequested()
            }
        }
        
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Style.capsuleBorderColor
        }
        
        // Current chat indicator (New Chat)
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: currentChatIndicator.implicitHeight + Style.marginS * 2
            color: Color.mPrimary
            radius: Style.radiusS
            visible: root.currentChatId === ""
            
            RowLayout {
                id: currentChatIndicator
                anchors.fill: parent
                anchors.margins: Style.marginS
                spacing: Style.marginXS
                
                NIcon {
                    icon: "message-circle-plus"
                    pointSize: Style.fontSizeS
                    color: Color.mOnPrimary
                }
                
                NText {
                    text: "New Chat"
                    font.pointSize: Style.fontSizeS
                    font.weight: Font.Medium
                    color: Color.mOnPrimary
                    Layout.fillWidth: true
                }
            }
        }
        
        // Chat list
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Color.mSurface
            radius: Style.radiusS
            clip: true
            
            ListView {
                id: chatListView
                anchors.fill: parent
                anchors.margins: Style.marginXXS
                spacing: Style.marginXXS
                clip: true
                model: root.chatList
                
                onContentYChanged: {
                    // Load more when scrolled near bottom (within 200px)
                    var nearBottom = (contentY + height) >= (contentHeight - 200);
                    if (nearBottom && !root.fetchingChats) {
                        root.loadMoreRequested();
                    }
                }
                
                delegate: ItemDelegate {
                    id: chatDelegate
                    width: chatListView.width
                    
                    readonly property bool isHovered: chatDelegate.hovered && root.currentChatId !== modelData.id
                    
                    contentItem: ColumnLayout {
                        spacing: Style.marginXXS
                        
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.marginXS
                            
                            NIcon {
                                icon: root.currentChatId === modelData.id ? "message-circle-check" : "message-circle"
                                pointSize: Style.fontSizeS
                                color: {
                                    if (root.currentChatId === modelData.id) return Color.mPrimary;
                                    if (chatDelegate.isHovered) return Color.mOnPrimary;
                                    return Color.mOnSurfaceVariant;
                                }
                            }
                            
                            NText {
                                text: {
                                    var t = modelData.title || "Untitled Chat";
                                    return t.length > 20 ? t.substring(0, 20) + "..." : t;
                                }
                                font.pointSize: Style.fontSizeS
                                font.weight: root.currentChatId === modelData.id ? Font.Medium : Font.Normal
                                color: {
                                    if (root.currentChatId === modelData.id) return Color.mPrimary;
                                    if (chatDelegate.isHovered) return Color.mOnPrimary;
                                    return Color.mOnSurface;
                                }
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        
                        NText {
                            text: {
                                var date = new Date(modelData.updated_at * 1000);
                                var now = new Date();
                                var diff = now - date;
                                var minutes = Math.floor(diff / 60000);
                                var hours = Math.floor(diff / 3600000);
                                var days = Math.floor(diff / 86400000);
                                
                                if (minutes < 1) return "Just now";
                                if (minutes < 60) return minutes + "m ago";
                                if (hours < 24) return hours + "h ago";
                                if (days < 7) return days + "d ago";
                                return date.toLocaleDateString();
                            }
                            font.pointSize: Style.fontSizeXS
                            color: chatDelegate.isHovered ? Color.mOnPrimary : Color.mOnSurfaceVariant
                            Layout.leftMargin: Style.fontSizeS + Style.marginXS
                        }
                    }
                    
                    highlighted: root.currentChatId === modelData.id
                    
                    background: Rectangle {
                        color: {
                            if (root.currentChatId === modelData.id) return Qt.alpha(Color.mPrimary, 0.1);
                            if (parent.hovered) return Color.mHover;
                            return "transparent";
                        }
                        radius: Style.radiusS
                        border.color: root.currentChatId === modelData.id ? Color.mPrimary : "transparent"
                        border.width: root.currentChatId === modelData.id ? 1 : 0
                    }
                    
                    onClicked: {
                        if (root.currentChatId !== modelData.id) {
                            root.chatSelected(modelData.id);
                        }
                    }
                }
                
                // Empty state
                Item {
                    anchors.fill: parent
                    visible: root.chatList.length === 0 && !root.fetchingChats
                    
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Style.marginS
                        
                        NIcon {
                            icon: "inbox"
                            pointSize: Style.fontSizeXXL
                            color: Color.mOnSurfaceVariant
                            Layout.alignment: Qt.AlignHCenter
                        }
                        
                        NText {
                            text: "No chats yet"
                            font.pointSize: Style.fontSizeS
                            color: Color.mOnSurfaceVariant
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
                
                // Loading state
                Item {
                    anchors.fill: parent
                    visible: root.fetchingChats
                    
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Style.marginS
                        
                        NIcon {
                            icon: "loader-2"
                            pointSize: Style.fontSizeXXL
                            color: Color.mPrimary
                            Layout.alignment: Qt.AlignHCenter
                            
                            RotationAnimation on rotation {
                                running: root.fetchingChats
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 1000
                            }
                        }
                        
                        NText {
                            text: "Loading chats..."
                            font.pointSize: Style.fontSizeS
                            color: Color.mOnSurfaceVariant
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
                
                ScrollIndicator.vertical: ScrollIndicator { }
            }
        }
        
        // Error display
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: chatsErrorContent.implicitHeight + Style.marginS * 2
            color: Qt.alpha(Color.mError, 0.2)
            radius: Style.radiusS
            visible: root.chatsError !== ""
            
            RowLayout {
                id: chatsErrorContent
                anchors.fill: parent
                anchors.margins: Style.marginS
                spacing: Style.marginXS
                
                NIcon {
                    icon: "alert-circle"
                    pointSize: Style.fontSizeXS
                    color: Color.mError
                }
                
                NText {
                    text: root.chatsError
                    font.pointSize: Style.fontSizeXS
                    color: Color.mError
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }
    }
}
