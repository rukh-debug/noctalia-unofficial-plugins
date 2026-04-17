import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.Commons
import qs.Widgets
import "components"

Item {
    id: root

    property var pluginApi: null

    function _normaliseTabIndex(value) {
        var index = Number(value)
        if (isNaN(index))
            return 1
        index = Math.round(index)
        return Math.max(0, Math.min(2, index))
    }

    function _restoreLastTab() {
        if (!pluginApi)
            return
        var savedIndex = _normaliseTabIndex(pluginApi?.pluginSettings?.lastPanelTabIndex)
        if (root.tabIndex !== savedIndex)
            root.tabIndex = savedIndex
    }

    function _saveLastTab() {
        if (!pluginApi)
            return
        var savedIndex = _normaliseTabIndex(root.tabIndex)
        if (pluginApi?.pluginSettings?.lastPanelTabIndex === savedIndex)
            return
        pluginApi.pluginSettings.lastPanelTabIndex = savedIndex
        pluginApi.saveSettings()
    }

    function _themeColor(name, fallback) {
        var value = Color ? Color[name] : null
        return value !== undefined && value !== null ? value : fallback
    }

    // ── SmartPanel contract ───────────────────────────────────────────────────
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true

    readonly property real screenWidth: pluginApi?.panelOpenScreen?.geometry?.width ?? 1920
    readonly property var panelWidthMap: ({ "small": 0.25, "medium": 0.5, "large": 0.75 })
    
    property real contentPreferredWidth: 
        screenWidth * (panelWidthMap[anime?.panelSize || "medium"])
    property real contentPreferredHeight: 980 * Style.uiScaleRatio

    anchors.fill: parent

    readonly property var anime: pluginApi?.mainInstance || null

    // ── Tab / navigation state ────────────────────────────────────────────────
    property int tabIndex:    1
    property int browseStack: 0
    property int libraryStack: 0
    property int feedStack: 0
    property bool settingsOpen: false

    onPluginApiChanged: root._restoreLastTab()

    Component.onCompleted: root._restoreLastTab()

    onTabIndexChanged: {
        root._saveLastTab()
        if (tabIndex === 2 && anime) {
            anime.fetchFollowingFeed(false)
            anime.markFeedNotificationsSeen()
        }
    }

    Rectangle {
        id: panelContainer
        anchors.fill: parent
        color: "transparent"
        radius: Style.radiusL

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── Main content ─────────────────────────────────────────────────
            Item {
                Layout.fillWidth:  true
                Layout.fillHeight: true
                StackLayout {
                    id: contentStack
                    anchors.fill: parent
                    currentIndex: root.tabIndex

                    // Browse tab
                    Item {
                        BrowseView {
                            anchors.fill: parent
                            pluginApi: root.pluginApi
                            z: 0
                            visible:  root.browseStack === 0
                            opacity:  visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            onAnimeSelected: function(show) {
                                if (root.anime) root.anime.fetchAnimeDetail(show)
                                root.browseStack = 1
                            }

                            onSettingsRequested: root.settingsOpen = true
                        }

                        DetailView {
                            anchors.fill: parent
                            pluginApi: root.pluginApi
                            z: 1
                            visible:  root.browseStack === 1
                            opacity:  visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            onBackRequested: {
                                root.browseStack = 0
                                if (root.anime) root.anime.clearDetail()
                            }
                        }
                    }

                    // Library tab
                    Item {
                        LibraryView {
                            anchors.fill: parent
                            pluginApi: root.pluginApi
                            z: 0
                            visible:  root.libraryStack === 0
                            opacity:  visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            onAnimeSelected: function(show) {
                                if (root.anime) root.anime.fetchAnimeDetail(show)
                                root.libraryStack = 1
                            }

                            onSettingsRequested: root.settingsOpen = true
                        }

                        DetailView {
                            anchors.fill: parent
                            pluginApi: root.pluginApi
                            z: 1
                            visible:  root.libraryStack === 1
                            opacity:  visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            onBackRequested: {
                                root.libraryStack = 0
                                if (root.anime) root.anime.clearDetail()
                            }
                        }
                    }

                    // Feed tab
                    Item {
                        FeedView {
                            anchors.fill: parent
                            pluginApi: root.pluginApi
                            z: 0
                            visible: root.feedStack === 0
                            opacity: visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            onAnimeSelected: function(show, nextEpisode) {
                                if (root.anime) root.anime.openAnimeDetail(show, nextEpisode)
                                root.feedStack = 1
                            }
                        }

                        DetailView {
                            anchors.fill: parent
                            pluginApi: root.pluginApi
                            z: 1
                            visible: root.feedStack === 1
                            opacity: visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            onBackRequested: {
                                root.feedStack = 0
                                if (root.anime) root.anime.clearDetail()
                            }
                        }
                    }
                }

                MultiEffect {
                    anchors.fill: contentStack
                    source: contentStack
                    blurEnabled: root.settingsOpen
                    blur: 1.0
                    blurMax: 56
                    transparentBorder: true
                    visible: root.settingsOpen
                    opacity: root.settingsOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }

                Rectangle {
                    anchors.fill: contentStack
                    visible: root.settingsOpen
                    color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.56)
                    opacity: root.settingsOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }

                SettingsView {
                    anchors.fill: parent
                    pluginApi: root.pluginApi
                    visible: root.settingsOpen
                    opacity: visible ? 1 : 0
                    z: 5
                    onBackRequested: root.settingsOpen = false
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }
            }

            // ── Bottom tab bar ────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 48
                color: "transparent"

                // Top hairline
                Rectangle {
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 1
                    color: _themeColor("mOutlineVariant",
                        _themeColor("mOutline", Color.mOnSurfaceVariant))
                    opacity: 0.4
                }

                Row {
                    anchors.fill: parent

                    Repeater {
                        model: [
                            { label: "Browse",   icon: "⊞" },
                            { label: "Library",  icon: "⊟" },
                            { label: "Feed",     icon: "◉" }
                        ]

                        delegate: Item {
                            width:  panelContainer.width / 3
                            height: parent.height

                            readonly property bool active: !root.settingsOpen && root.tabIndex === index

                            Rectangle {
                                anchors.fill: parent
                                color: tabArea.containsMouse && !active
                                    ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)
                                    : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 2

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.icon
                                    font.pixelSize: 13
                                    color: active
                                        ? Color.mPrimary
                                        : (tabArea.containsMouse ? Color.mPrimary : Color.mOnSurfaceVariant)
                                    opacity: active || tabArea.containsMouse ? 1 : 0.5
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                    Behavior on opacity { NumberAnimation { duration: 180 } }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label
                                    font.pixelSize: 10
                                    font.letterSpacing: 0.6
                                    color: active
                                        ? Color.mPrimary
                                        : (tabArea.containsMouse ? Color.mPrimary : Color.mOnSurfaceVariant)
                                    opacity: active || tabArea.containsMouse ? 1 : 0.5
                                    Behavior on color { ColorAnimation { duration: 180 } }
                                    Behavior on opacity { NumberAnimation { duration: 180 } }
                                }
                            }

                            Rectangle {
                                visible: index === 2 && (anime?.feedUnreadCount ?? 0) > 0
                                anchors {
                                    top: parent.top
                                    right: parent.right
                                    topMargin: 6
                                    rightMargin: Math.max(12, parent.width * 0.24)
                                }
                                height: 18
                                width: Math.max(feedBadgeText.implicitWidth + 10, 18)
                                radius: 9
                                color: Color.mPrimary
                                border.width: 1
                                border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.4)

                                Text {
                                    id: feedBadgeText
                                    anchors.centerIn: parent
                                    text: (anime?.feedUnreadCount ?? 0) > 99 ? "99+" : String(anime?.feedUnreadCount ?? 0)
                                    font.pixelSize: 8
                                    font.bold: true
                                    color: Color.mOnPrimary
                                }
                            }

                            Rectangle {
                                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                                width:  active ? 28 : 0
                                height: 2; radius: 1
                                color: Color.mPrimary
                                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                id: tabArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    root.settingsOpen = false
                                    root.tabIndex = index
                                    if (index === 2 && root.anime) {
                                        root.anime.fetchFollowingFeed(false)
                                        root.anime.markFeedNotificationsSeen()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
