import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
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

    function _withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function _shapeMultX(cornerState) {
        return cornerState === 1 ? -1 : 1
    }

    function _shapeMultY(cornerState) {
        return cornerState === 2 ? -1 : 1
    }

    function _shapeArcDirection(multX, multY) {
        return ((multX < 0) !== (multY < 0)) ? PathArc.Counterclockwise : PathArc.Clockwise
    }

    function _downloadStatePriority(item) {
        var state = String(item?.state || "").toLowerCase()
        if (state === "resolving" || state === "preparing" || state === "downloading")
            return 0
        if (state === "queued")
            return 1
        return 2
    }

    function _orderedDownloadItems(items) {
        var list = Array.isArray(items) ? items.slice() : []
        list.sort(function(a, b) {
            var priorityDelta = root._downloadStatePriority(a) - root._downloadStatePriority(b)
            if (priorityDelta !== 0)
                return priorityDelta
            return Number(a?.createdAt || 0) - Number(b?.createdAt || 0)
        })
        return list
    }

    function _downloadToneColor(item) {
        var tone = String(item?.tone || "").toLowerCase()
        if (tone === "error")
            return Color.mError
        if (tone === "success")
            return Color.mTertiary
        return Color.mPrimary
    }

    function _downloadTitleText(item) {
        var title = String(item?.title || "Episode")
        var episodeNumber = String(item?.episodeNumber || "")
        return episodeNumber.length > 0 ? (title + " · Ep. " + episodeNumber) : title
    }

    function _downloadDetailText(item) {
        var detail = String(item?.detail || "").trim()
        if (detail.length > 0)
            return detail
        return String(item?.targetPath || "")
    }

    function _downloadIsActive(item) {
        var state = String(item?.state || "").toLowerCase()
        return state === "resolving" || state === "preparing" || state === "downloading"
    }

    function _downloadProgressValue(item) {
        var explicit = Number(item?.progress)
        if (!isNaN(explicit) && explicit >= 0)
            return Math.max(0, Math.min(1, explicit))

        var state = String(item?.state || "").toLowerCase()
        if (state === "queued")
            return 0
        if (state === "resolving")
            return 0.16
        if (state === "preparing")
            return 0.28
        if (state === "downloading")
            return 0.56
        if (state === "completed")
            return 1
        if (state === "failed")
            return 0.34
        return 0.08
    }

    function _downloadProgressLabel(item) {
        var state = String(item?.state || "").toLowerCase()
        if (state === "queued")
            return "Waiting"
        if (state === "failed")
            return "Failed"
        return Math.round(root._downloadProgressValue(item) * 100) + "%"
    }

    function _downloadHasLocation(item) {
        return String(item?.targetPath || "").trim().length > 0
    }

    function _downloadCanClear(item) {
        return String(item?.state || "").toLowerCase() === "completed"
    }

    function _downloadCanCancel(item) {
        var state = String(item?.state || "").toLowerCase()
        return state === "queued"
            || state === "resolving"
            || state === "preparing"
            || state === "downloading"
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
    property bool settingsOpen: anime?.panelSettingsOpen ?? false
    readonly property var orderedDownloadStatusItems:
        root._orderedDownloadItems(anime?.downloadStatusItems ?? [])
    readonly property var visibleDownloadStatusItems:
        orderedDownloadStatusItems.slice(0, 4)
    readonly property int hiddenDownloadStatusCount:
        Math.max(0, orderedDownloadStatusItems.length - visibleDownloadStatusItems.length)
    readonly property bool downloadDrawerVisible:
        !root.settingsOpen && visibleDownloadStatusItems.length > 0
    property bool downloadDrawerCollapsed: false

    onDownloadDrawerVisibleChanged: {
        if (!downloadDrawerVisible)
            root.downloadDrawerCollapsed = false
    }

    onPluginApiChanged: root._restoreLastTab()

    Component.onCompleted: root._restoreLastTab()

    onTabIndexChanged: {
        root._saveLastTab()
        if (tabIndex === 2 && anime) {
            anime.fetchFollowingFeed(false)
            anime.markFeedNotificationsSeen()
        }
    }

    onSettingsOpenChanged: {
        if (anime && anime.panelSettingsOpen !== settingsOpen)
            anime.panelSettingsOpen = settingsOpen
    }

    Rectangle {
        id: panelContainer
        anchors.fill: parent
        color: "transparent"
        radius: Style.radiusL
        clip: root.settingsOpen

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

                ShaderEffectSource {
                    id: settingsBackdropSource
                    anchors.fill: contentStack
                    visible: root.settingsOpen
                    live: root.settingsOpen
                    hideSource: false
                    recursive: true
                    sourceItem: contentStack
                }

                FastBlur {
                    anchors.fill: contentStack
                    visible: root.settingsOpen
                    source: settingsBackdropSource
                    radius: 28
                    transparentBorder: true
                    layer.enabled: visible
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: contentStack.width
                            height: contentStack.height
                            color: root._themeColor("mOnSurface", Color.mOnSurface)
                            topLeftRadius: Style.radiusL
                            topRightRadius: Style.radiusL
                            bottomLeftRadius: 0
                            bottomRightRadius: 0
                        }
                    }
                }

                Rectangle {
                    anchors.fill: contentStack
                    visible: root.settingsOpen
                    color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.7)
                    topLeftRadius: Style.radiusL
                    topRightRadius: Style.radiusL
                    bottomLeftRadius: 0
                    bottomRightRadius: 0
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

            // ── Bottom navigation + download drawer ──────────────────────────
            Item {
                id: bottomChrome
                Layout.fillWidth: true
                implicitHeight: bottomBarHeight

                readonly property real bottomBarHeight: 48
                readonly property real drawerOverlap: 14
                readonly property real drawerLift: 13
                readonly property real drawerHorizontalNudge: 19
                readonly property real drawerLeftMargin:
                    Math.max(0, Math.round(panelContainer.width * (2 / 3)) - drawerHorizontalNudge)
                readonly property real drawerRadius: Style.radiusL
                readonly property real drawerHeight: Math.min(
                    154,
                    Math.max(40, 10 + root.visibleDownloadStatusItems.length * 26 + (root.hiddenDownloadStatusCount > 0 ? 12 : 0))
                )
                readonly property real drawerCollapsedHeight: 14
                readonly property int drawerMotionDuration: 260
                readonly property real collapsedIndicatorWidth: 58
                readonly property real collapsedIndicatorHeight: 16
                readonly property color chromeFill:
                    Color.mSurface
                readonly property color chromeBorder:
                    _themeColor("mOutlineVariant", _themeColor("mOutline", Color.mOnSurfaceVariant))
                readonly property color chromeHighlight:
                    root._withAlpha(_themeColor("mOnSurface", Color.mOnSurface), 0.12)

                Item {
                    id: downloadDrawer
                    anchors {
                        left: bottomBar.left
                        leftMargin: bottomChrome.drawerLeftMargin
                        right: bottomBar.right
                        rightMargin: bottomChrome.drawerHorizontalNudge
                        bottom: bottomBar.top
                        bottomMargin: bottomChrome.drawerLift - bottomChrome.drawerOverlap
                    }
                    height: !root.downloadDrawerVisible
                        ? 0
                        : (root.downloadDrawerCollapsed
                            ? bottomChrome.drawerCollapsedHeight
                            : bottomChrome.drawerHeight)
                    visible: root.downloadDrawerVisible || height > 0
                    opacity: root.downloadDrawerVisible && !root.downloadDrawerCollapsed ? 1 : 0
                    z: 3
                    clip: true

                    Behavior on opacity { NumberAnimation { duration: bottomChrome.drawerMotionDuration; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: bottomChrome.drawerMotionDuration; easing.type: Easing.OutCubic } }

                    readonly property int topLeftCornerState: 0
                    readonly property int topRightCornerState: 0
                    readonly property int bottomLeftCornerState: 1
                    readonly property int bottomRightCornerState: 1
                    readonly property real effectiveRadius:
                        Math.min(bottomChrome.drawerRadius, Math.min(width, height) / 2)

                    readonly property real tlMultX: root._shapeMultX(topLeftCornerState)
                    readonly property real tlMultY: root._shapeMultY(topLeftCornerState)
                    readonly property real trMultX: root._shapeMultX(topRightCornerState)
                    readonly property real trMultY: root._shapeMultY(topRightCornerState)
                    readonly property real brMultX: root._shapeMultX(bottomRightCornerState)
                    readonly property real brMultY: root._shapeMultY(bottomRightCornerState)
                    readonly property real blMultX: root._shapeMultX(bottomLeftCornerState)
                    readonly property real blMultY: root._shapeMultY(bottomLeftCornerState)

                    Shape {
                        anchors.fill: parent
                        antialiasing: true

                        ShapePath {
                            strokeWidth: 1
                            strokeColor: root._withAlpha(bottomChrome.chromeBorder, 0.28)
                            fillColor: bottomChrome.chromeFill
                            startX: downloadDrawer.effectiveRadius * downloadDrawer.tlMultX
                            startY: 0

                            PathLine {
                                relativeX: downloadDrawer.width
                                    - downloadDrawer.effectiveRadius * downloadDrawer.tlMultX
                                    - downloadDrawer.effectiveRadius * downloadDrawer.trMultX
                                relativeY: 0
                            }

                            PathArc {
                                relativeX: downloadDrawer.effectiveRadius * downloadDrawer.trMultX
                                relativeY: downloadDrawer.effectiveRadius * downloadDrawer.trMultY
                                radiusX: downloadDrawer.effectiveRadius
                                radiusY: downloadDrawer.effectiveRadius
                                direction: root._shapeArcDirection(downloadDrawer.trMultX, downloadDrawer.trMultY)
                            }

                            PathLine {
                                relativeX: 0
                                relativeY: downloadDrawer.height
                                    - downloadDrawer.effectiveRadius * downloadDrawer.trMultY
                                    - downloadDrawer.effectiveRadius * downloadDrawer.brMultY
                            }

                            PathArc {
                                relativeX: -downloadDrawer.effectiveRadius * downloadDrawer.brMultX
                                relativeY: downloadDrawer.effectiveRadius * downloadDrawer.brMultY
                                radiusX: downloadDrawer.effectiveRadius
                                radiusY: downloadDrawer.effectiveRadius
                                direction: root._shapeArcDirection(downloadDrawer.brMultX, downloadDrawer.brMultY)
                            }

                            PathLine {
                                relativeX: -(downloadDrawer.width
                                    - downloadDrawer.effectiveRadius * downloadDrawer.brMultX
                                    - downloadDrawer.effectiveRadius * downloadDrawer.blMultX)
                                relativeY: 0
                            }

                            PathArc {
                                relativeX: -downloadDrawer.effectiveRadius * downloadDrawer.blMultX
                                relativeY: -downloadDrawer.effectiveRadius * downloadDrawer.blMultY
                                radiusX: downloadDrawer.effectiveRadius
                                radiusY: downloadDrawer.effectiveRadius
                                direction: root._shapeArcDirection(downloadDrawer.blMultX, downloadDrawer.blMultY)
                            }

                            PathLine {
                                relativeX: 0
                                relativeY: -(downloadDrawer.height
                                    - downloadDrawer.effectiveRadius * downloadDrawer.blMultY
                                    - downloadDrawer.effectiveRadius * downloadDrawer.tlMultY)
                            }

                            PathArc {
                                relativeX: downloadDrawer.effectiveRadius * downloadDrawer.tlMultX
                                relativeY: -downloadDrawer.effectiveRadius * downloadDrawer.tlMultY
                                radiusX: downloadDrawer.effectiveRadius
                                radiusY: downloadDrawer.effectiveRadius
                                direction: root._shapeArcDirection(downloadDrawer.tlMultX, downloadDrawer.tlMultY)
                            }
                        }
                    }

                    Rectangle {
                        visible: downloadDrawer.height > bottomChrome.drawerCollapsedHeight + 6
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            topMargin: 1
                            leftMargin: bottomChrome.drawerRadius + 2
                            rightMargin: bottomChrome.drawerRadius + 2
                        }
                        height: 1
                        color: bottomChrome.chromeHighlight
                        opacity: 0.9
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 6
                        width: 34
                        height: 3
                        radius: 2
                        color: root._withAlpha(Color.mOnSurfaceVariant, 0.42)
                    }

                    MouseArea {
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                        }
                        height: 12
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.downloadDrawerCollapsed = true
                    }

                    Column {
                        id: drawerContent
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                            topMargin: 16
                            leftMargin: 14
                            rightMargin: 14
                            bottomMargin: bottomChrome.drawerRadius + 2
                        }
                        spacing: 6
                        opacity: root.downloadDrawerVisible && !root.downloadDrawerCollapsed ? 1 : 0
                        y: root.downloadDrawerCollapsed ? 8 : 0

                        Behavior on opacity { NumberAnimation { duration: bottomChrome.drawerMotionDuration; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: bottomChrome.drawerMotionDuration; easing.type: Easing.OutCubic } }

                        Column {
                            id: downloadItemsColumn
                            width: parent.width
                            spacing: 6

                            add: Transition {
                                ParallelAnimation {
                                    NumberAnimation {
                                        properties: "x,y"
                                        duration: 220
                                        easing.type: Easing.OutCubic
                                    }
                                    NumberAnimation {
                                        properties: "opacity"
                                        from: 0
                                        to: 1
                                        duration: 160
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            move: Transition {
                                NumberAnimation {
                                    properties: "x,y"
                                    duration: 220
                                    easing.type: Easing.OutCubic
                                }
                            }

                            populate: Transition {
                                NumberAnimation {
                                    properties: "opacity"
                                    from: 0
                                    to: 1
                                    duration: 140
                                }
                            }

                            Repeater {
                                model: root.visibleDownloadStatusItems

                                delegate: Item {
                                    id: titleRow
                                    required property var modelData

                                    width: parent.width
                                    height: 24
                                    opacity: 1
                                    readonly property bool canOpenLocation:
                                        root._downloadHasLocation(modelData)

                                    Behavior on y {
                                        NumberAnimation {
                                            duration: 220
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    Row {
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            top: parent.top
                                            leftMargin: 0
                                            rightMargin: 0
                                        }
                                        spacing: 8

                                        Item {
                                            id: titleArea
                                            width: parent.width - trailingRow.width - 8
                                            height: 12

                                            property bool hovered: titleMouse.containsMouse

                                            Text {
                                                id: titleText
                                                width: parent.width - (openHint.visible ? openHint.implicitWidth + 6 : 0)
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: root._downloadTitleText(modelData)
                                                font.pixelSize: 9
                                                font.bold: false
                                                font.underline: titleArea.hovered && titleRow.canOpenLocation
                                                color: titleArea.hovered && titleRow.canOpenLocation
                                                    ? Color.mPrimary
                                                    : Color.mOnSurface
                                                elide: Text.ElideRight
                                                opacity: 0.94
                                            }

                                            Text {
                                                id: openHint
                                                anchors {
                                                    right: parent.right
                                                    verticalCenter: parent.verticalCenter
                                                }
                                                visible: titleArea.hovered && titleRow.canOpenLocation
                                                text: "Open"
                                                font.pixelSize: 7
                                                font.bold: true
                                                color: Color.mPrimary
                                                opacity: 0.9
                                            }

                                            MouseArea {
                                                id: titleMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: titleRow.canOpenLocation
                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                onClicked: {
                                                    if (root.anime)
                                                        root.anime.openDownloadLocation(String(modelData?.targetPath || ""))
                                                }
                                            }
                                        }

                                        Row {
                                            id: trailingRow
                                            spacing: 6

                                            Rectangle {
                                                visible: root._downloadCanClear(modelData) || root._downloadCanCancel(modelData)
                                                width: 14
                                                height: 14
                                                radius: 7
                                                color: clearMouse.containsMouse
                                                    ? Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.16)
                                                    : "transparent"
                                                border.width: 1
                                                border.color: root._withAlpha(
                                                    clearMouse.containsMouse ? Color.mError : bottomChrome.chromeBorder,
                                                    clearMouse.containsMouse ? 0.42 : 0.22
                                                )

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "×"
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    color: clearMouse.containsMouse ? Color.mError : Color.mOnSurfaceVariant
                                                    opacity: 0.9
                                                }

                                                MouseArea {
                                                    id: clearMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (!root.anime)
                                                            return
                                                        if (root._downloadCanClear(modelData))
                                                            root.anime.clearCompletedDownloadStatus(String(modelData?.id || ""))
                                                        else if (root._downloadCanCancel(modelData))
                                                            root.anime.cancelEpisodeDownloadStatus(String(modelData?.id || ""))
                                                    }
                                                }
                                            }

                                            Text {
                                                id: trailingText
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: root._downloadProgressLabel(modelData)
                                                font.pixelSize: 9
                                                color: Color.mOnSurface
                                                opacity: 0.86
                                            }
                                        }
                                    }

                                    Rectangle {
                                        id: progressTrack
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            bottom: parent.bottom
                                            bottomMargin: 0
                                        }
                                        height: 2.5
                                        radius: 2
                                        color: Qt.rgba(Color.mOnSurface.r, Color.mOnSurface.g, Color.mOnSurface.b, 0.18)
                                        clip: true

                                        Rectangle {
                                            width: parent.width * root._downloadProgressValue(modelData)
                                            height: parent.height
                                            radius: parent.radius
                                            color: _themeColor("mPrimary", Color.mPrimary)
                                            opacity: 0.9

                                            Rectangle {
                                                id: progressShine
                                                visible: root._downloadIsActive(modelData)
                                                width: Math.max(18, parent.width * 0.24)
                                                height: parent.height
                                                radius: parent.radius
                                                color: root._withAlpha(_themeColor("mOnPrimary", Color.mOnPrimary), 0.42)
                                                x: -width

                                                SequentialAnimation on x {
                                                    running: progressShine.visible && downloadDrawer.visible
                                                    loops: Animation.Infinite
                                                    NumberAnimation {
                                                        from: -progressShine.width
                                                        to: parent.width
                                                        duration: 1100
                                                        easing.type: Easing.InOutCubic
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                visible: root.hiddenDownloadStatusCount > 0
                                width: parent.width
                                height: 10
                                clip: true

                                Rectangle {
                                    anchors {
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                    }
                                    width: overflowText.implicitWidth + 7
                                    height: 10
                                    radius: 5
                                    color: _themeColor("mPrimary", Color.mPrimary)
                                    border.width: 1
                                    border.color: root._withAlpha(_themeColor("mOnPrimary", Color.mOnPrimary), 0.18)

                                    Text {
                                        id: overflowText
                                        anchors.centerIn: parent
                                        text: "+" + String(root.hiddenDownloadStatusCount)
                                        font.pixelSize: 6
                                        font.bold: true
                                        color: _themeColor("mOnPrimary", Color.mOnPrimary)
                                        opacity: 0.9
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    id: collapsedIndicator
                    anchors {
                        horizontalCenter: downloadDrawer.horizontalCenter
                        bottom: bottomBar.top
                        bottomMargin: -2
                    }
                    width: bottomChrome.collapsedIndicatorWidth
                    height: bottomChrome.collapsedIndicatorHeight
                    visible: opacity > 0
                    opacity: root.downloadDrawerVisible && root.downloadDrawerCollapsed ? 1 : 0
                    scale: root.downloadDrawerVisible && root.downloadDrawerCollapsed ? 1 : 0.92
                    z: 3

                    Behavior on opacity { NumberAnimation { duration: bottomChrome.drawerMotionDuration; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: bottomChrome.drawerMotionDuration; easing.type: Easing.OutCubic } }

                    readonly property real effectiveRadius:
                        Math.min(bottomChrome.drawerRadius, Math.min(width, height) / 2)

                    Rectangle {
                        anchors.fill: parent
                        radius: collapsedIndicator.effectiveRadius
                        color: bottomChrome.chromeFill
                        border.width: 1
                        border.color: root._withAlpha(bottomChrome.chromeBorder, 0.28)
                    }

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: collapsedIndicator.effectiveRadius
                        color: bottomChrome.chromeFill
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 22
                        height: 3
                        radius: 2
                        color: root._withAlpha(Color.mOnSurfaceVariant, 0.42)
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.downloadDrawerCollapsed = false
                    }
                }

                Item {
                    id: bottomBar
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: bottomChrome.bottomBarHeight
                    z: 2

                    Rectangle {
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            topMargin: 1
                            leftMargin: 1
                            rightMargin: 1
                        }
                        height: 1
                        radius: 1
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
                                width: panelContainer.width / 3
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
                                    width: active ? 28 : 0
                                    height: 2
                                    radius: 1
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
}
