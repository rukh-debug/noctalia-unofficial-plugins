import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons

Item {
    id: feedView

    property var pluginApi: null
    readonly property var anime: pluginApi?.mainInstance || null
    readonly property var alertItems: anime?.feedList ?? []
    readonly property var upcomingItems: anime?.feedUpcomingList ?? []
    readonly property var feedSummary: anime?.feedSummary ?? ({ alerts: 0, upcoming: 0, following: 0 })
    readonly property bool hasAnyContent: alertItems.length > 0 || upcomingItems.length > 0

    signal animeSelected(var show, string nextEpisode)

    function _themeColor(name, fallback) {
        var value = Color ? Color[name] : null
        return value !== undefined && value !== null ? value : fallback
    }

    function _outlineVariantColor() {
        return _themeColor("mOutlineVariant",
            _themeColor("mOutline", Color.mOnSurfaceVariant))
    }

    function _showFromEntry(entry, posterOverride) {
        if (!entry) return null
        return {
            id: entry.id,
            name: entry.name || "",
            englishName: entry.englishName || "",
            nativeName: entry.nativeName || "",
            thumbnail: entry.thumbnail || posterOverride || "",
            score: entry.score,
            type: entry.type || "",
            episodeCount: entry.episodeCount || "",
            availableEpisodes: entry.availableEpisodes || { sub: 0, dub: 0, raw: 0 },
            season: entry.season || null,
            providerRefs: entry.providerRefs || ({})
        }
    }

    function _showFromFeedItem(item) {
        if (!item) return null
        if (item.providerRefs && item.providerRefs.metadata)
            return _showFromEntry(item, item.poster || "")
        if (!anime) return null
        return _showFromEntry(anime.getLibraryEntry(item.id), item.poster || "")
    }

    function openEntry(item) {
        var show = _showFromFeedItem(item)
        if (!show) return
        feedView.animeSelected(show, String(item.nextEpisode || ""))
    }

    function playNextForItem(item) {
        var show = _showFromFeedItem(item)
        if (!show || !anime) return
        anime.playNextForShow(show, String(item.nextEpisode || ""))
    }

    function updatedLabel() {
        var ts = anime?.feedLastFetchedAt || 0
        if (ts <= 0)
            return "Not updated yet"
        var diff = Math.max(0, Math.floor((Date.now() - ts) / 1000))
        if (diff < 15)
            return "Updated just now"
        if (diff < 60)
            return "Updated " + diff + "s ago"
        if (diff < 3600)
            return "Updated " + Math.floor(diff / 60) + "m ago"
        if (diff < 86400)
            return "Updated " + Math.floor(diff / 3600) + "h ago"
        return "Updated " + Math.floor(diff / 86400) + "d ago"
    }

    function _timeUntilText(item) {
        var seconds = Number(item?.timeUntilAiring || 0)
        if (seconds <= 0) {
            var airingAt = Number(item?.airingAt || 0)
            if (airingAt > 0)
                seconds = Math.max(0, Math.floor(airingAt - (Date.now() / 1000)))
        }
        if (seconds <= 0)
            return "soon"
        if (seconds < 3600)
            return Math.max(1, Math.floor(seconds / 60)) + "m"
        if (seconds < 86400)
            return Math.max(1, Math.floor(seconds / 3600)) + "h"
        return Math.max(1, Math.floor(seconds / 86400)) + "d"
    }

    function _alertHeadline(item) {
        var latest = String(item?.latestReleasedEpisode || "")
        return latest.length > 0 ? "Episode " + latest + " aired" : "New episode available"
    }

    function _alertSubtitle(item) {
        var watched = String(item?.watchedThrough || "")
        var gap = Number(item?.watchGap || 0)
        if (watched.length > 0 && gap <= 1)
            return "You were caught up through episode " + watched
        if (watched.length > 0 && gap === 2)
            return "You were one episode behind before this release"
        return item?.releaseText || "Ready to catch up"
    }

    function _upcomingHeadline(item) {
        var nextEpisode = String(item?.nextEpisode || "")
        if (nextEpisode.length > 0)
            return "Episode " + nextEpisode + " airs in " + _timeUntilText(item)
        return "Next release is scheduled"
    }

    function _upcomingSubtitle(item) {
        var watched = String(item?.watchedThrough || "")
        if (watched.length > 0)
            return "Current through episode " + watched
        return "Currently on schedule"
    }

    function _summaryValue(value) {
        return String(Math.max(0, Number(value || 0)))
    }

    function _markSeenIfVisible() {
        if (visible && anime)
            anime.markFeedNotificationsSeen()
    }

    onVisibleChanged: _markSeenIfVisible()

    Connections {
        target: anime
        ignoreUnknownSignals: true

        function onFeedListChanged() {
            feedView._markSeenIfVisible()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            height: 56
            color: "transparent"
            z: 2

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1
                color: _outlineVariantColor()
                opacity: 0.5
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 18; rightMargin: 10 }
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 19
                    color: Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.72)
                    border.width: 1
                    border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.18)

                    Row {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 14
                        }
                        spacing: 0

                        Text {
                            text: "A"
                            font.pixelSize: 22
                            font.letterSpacing: 1
                            color: Color.mPrimary
                        }
                        Text {
                            text: "lerts"
                            font.pixelSize: 22
                            font.letterSpacing: 1
                            color: Color.mOnSurface
                            opacity: 0.85
                        }
                    }
                }

                HoverIconButton {
                    text: "↻"
                    iconPixelSize: 16
                    onClicked: if (anime) anime.fetchFollowingFeed(true)
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                visible: (anime?.isFetchingFeed ?? false) && !feedView.hasAnyContent

                Column {
                    anchors.centerIn: parent
                    spacing: 14

                    Rectangle {
                        width: 28
                        height: 28
                        radius: 14
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: "transparent"
                        border.color: Color.mPrimary
                        border.width: 2
                        RotationAnimator on rotation {
                            from: 0
                            to: 360
                            duration: 800
                            loops: Animation.Infinite
                            running: parent.visible
                            easing.type: Easing.Linear
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "checking followed shows"
                        color: Color.mOnSurfaceVariant
                        font.pixelSize: 11
                        font.letterSpacing: 2
                        opacity: 0.7
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: !(anime?.isFetchingFeed ?? false) && (anime?.feedError?.length ?? 0) > 0

                Column {
                    anchors.centerIn: parent
                    spacing: 10

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Feed unavailable"
                        font.pixelSize: 15
                        font.bold: true
                        color: Color.mOnSurface
                    }

                    Text {
                        width: 320
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: anime?.feedError ?? ""
                        font.pixelSize: 11
                        color: Color.mOnSurfaceVariant
                        opacity: 0.74
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: !(anime?.isFetchingFeed ?? false)
                    && (anime?.feedError?.length ?? 0) === 0
                    && !feedView.hasAnyContent

                Rectangle {
                    width: Math.min(parent.width - 28, 380)
                    anchors.centerIn: parent
                    radius: 22
                    color: Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.72)
                    border.width: 1
                    border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.16)
                    implicitHeight: emptyColumn.implicitHeight + 36

                    Column {
                        id: emptyColumn
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 10

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 42
                            height: 42
                            radius: 21
                            color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)

                            Text {
                                anchors.centerIn: parent
                                text: (anime?.libraryList?.length ?? 0) > 0 ? "✓" : "⊡"
                                font.pixelSize: 19
                                color: Color.mPrimary
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: (anime?.libraryList?.length ?? 0) > 0
                                ? "No new release alerts"
                                : "Your library is empty"
                            font.pixelSize: 15
                            font.bold: true
                            color: Color.mOnSurface
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            lineHeight: 1.35
                            text: (anime?.libraryList?.length ?? 0) > 0
                                ? "Feed tracks releasing seasons you are actively watching and close to caught up on. New episodes appear here when the next release becomes relevant."
                                : "Add anime to your library and keep a releasing season in Watching so Feed can surface new episode releases as they drop."
                            font.pixelSize: 11
                            color: Color.mOnSurfaceVariant
                            opacity: 0.74
                        }
                    }
                }
            }

            Flickable {
                id: feedScroll
                anchors.fill: parent
                anchors.margins: 10
                visible: feedView.hasAnyContent && (anime?.feedError?.length ?? 0) === 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: contentColumn.implicitHeight

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 3
                        color: Color.mPrimary
                        opacity: 0.45
                        radius: 2
                    }
                }

                Column {
                    id: contentColumn
                    width: feedScroll.width
                    spacing: 14

                    Flow {
                        width: parent.width
                        spacing: 10

                        Repeater {
                            model: [
                                {
                                    title: "Unread",
                                    value: feedView._summaryValue(anime?.feedUnreadCount || 0),
                                    accent: "primary",
                                    subtitle: ""
                                },
                                {
                                    title: "Watching Closely",
                                    value: feedView._summaryValue(feedSummary.following),
                                    accent: "surface",
                                    subtitle: ""
                                },
                                {
                                    title: anime?.isFetchingFeed ? "Refreshing…" : feedView.updatedLabel(),
                                    value: feedSummary.alerts > 0
                                        ? (feedSummary.alerts + " release alerts")
                                        : (feedSummary.upcoming > 0 ? (feedSummary.upcoming + " upcoming releases") : "No pending alerts"),
                                    accent: anime?.isFetchingFeed ? "primary" : "surface",
                                    subtitle: "wide"
                                }
                            ]

                            delegate: Rectangle {
                                readonly property real compactWidth:
                                    Math.max(Math.floor((parent.width - parent.spacing * 2) / 3), 120)
                                width: modelData.subtitle === "wide"
                                    ? (parent.width >= 720
                                        ? Math.max(parent.width - compactWidth * 2 - parent.spacing * 2, compactWidth)
                                        : parent.width)
                                    : compactWidth
                                height: 68
                                radius: 18
                                color: Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.64)
                                border.width: 1
                                border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.14)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 4

                                    Text {
                                        text: modelData.title
                                        font.pixelSize: 10
                                        color: modelData.accent === "primary" ? Color.mPrimary : Color.mOnSurfaceVariant
                                        opacity: 0.84
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: modelData.value
                                        font.pixelSize: modelData.subtitle === "wide" ? 14 : 22
                                        font.bold: true
                                        color: modelData.accent === "primary" ? Color.mPrimary : Color.mOnSurface
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: alertItems.length > 0 ? alertColumn.implicitHeight : 0
                        visible: alertItems.length > 0

                        Column {
                            id: alertColumn
                            width: parent.width
                            spacing: 10

                            Row {
                                width: parent.width
                                spacing: 8

                                Text {
                                    text: "New Releases"
                                    font.pixelSize: 14
                                    font.bold: true
                                    color: Color.mOnSurface
                                }

                                Rectangle {
                                    height: 20
                                    width: alertCountText.implicitWidth + 14
                                    radius: 10
                                    color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)
                                    border.width: 1
                                    border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.28)

                                    Text {
                                        id: alertCountText
                                        anchors.centerIn: parent
                                        text: alertItems.length + " alerts"
                                        font.pixelSize: 9
                                        font.bold: true
                                        font.letterSpacing: 0.4
                                        color: Color.mPrimary
                                    }
                                }
                            }

                            Repeater {
                                model: alertItems

                                delegate: Rectangle {
                                    readonly property var itemData: modelData
                                    readonly property bool unread: anime?.isFeedItemUnread(itemData) ?? false
                                    readonly property bool hovered: alertCardArea.containsMouse

                                    width: parent.width
                                    height: 108
                                    radius: 20
                                    color: Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, unread ? 0.78 : 0.64)
                                    border.width: 1
                                    border.color: unread
                                        ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.34)
                                        : Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)
                                    clip: true

                                    Rectangle {
                                        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                                        width: unread ? 5 : 3
                                        radius: width / 2
                                        color: unread ? Color.mPrimary : Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.18)
                                    }

                                    MouseArea {
                                        id: alertCardArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: feedView.openEntry(itemData)
                                    }

                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 12

                                        Rectangle {
                                            id: alertPoster
                                            width: 62
                                            height: parent.height
                                            radius: 14
                                            color: "transparent"
                                            clip: true
                                             // OpacityMask removed — parent clip: true + radius handles rounding

                                            Image {
                                                anchors.fill: parent
                                                source: itemData.poster || ""
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                cache: true
                                            }
                                        }

                                        Column {
                                            width: parent.width - 62 - 96 - 24
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 6

                                            Row {
                                                spacing: 6

                                                Rectangle {
                                                    visible: unread
                                                    height: 18
                                                    width: unreadText.implicitWidth + 10
                                                    radius: 9
                                                    color: Color.mPrimary

                                                    Text {
                                                        id: unreadText
                                                        anchors.centerIn: parent
                                                        text: "New"
                                                        font.pixelSize: 8
                                                        font.bold: true
                                                        color: Color.mOnPrimary
                                                    }
                                                }

                                                Rectangle {
                                                    height: 18
                                                    width: releasedText.implicitWidth + 10
                                                    radius: 9
                                                    color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)
                                                    border.width: 1
                                                    border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.22)

                                                    Text {
                                                        id: releasedText
                                                        anchors.centerIn: parent
                                                        text: "Ep " + (itemData.latestReleasedEpisode || "?")
                                                        font.pixelSize: 8
                                                        font.bold: true
                                                        color: Color.mPrimary
                                                    }
                                                }

                                                Rectangle {
                                                    visible: String(itemData.feedReason || "").length > 0
                                                    height: 18
                                                    width: reasonText.implicitWidth + 10
                                                    radius: 9
                                                    color: Qt.rgba(Color.mTertiary.r, Color.mTertiary.g, Color.mTertiary.b, 0.14)
                                                    border.width: 1
                                                    border.color: Qt.rgba(Color.mTertiary.r, Color.mTertiary.g, Color.mTertiary.b, 0.24)

                                                    Text {
                                                        id: reasonText
                                                        anchors.centerIn: parent
                                                        text: itemData.feedReason || ""
                                                        font.pixelSize: 8
                                                        font.bold: true
                                                        color: Color.mTertiary
                                                    }
                                                }

                                                Rectangle {
                                                    visible: Number(itemData.timeUntilAiring || 0) > 0
                                                    height: 18
                                                    width: nextText.implicitWidth + 10
                                                    radius: 9
                                                    color: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.14)
                                                    border.width: 1
                                                    border.color: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.24)

                                                    Text {
                                                        id: nextText
                                                        anchors.centerIn: parent
                                                        text: "Next in " + feedView._timeUntilText(itemData)
                                                        font.pixelSize: 8
                                                        font.bold: true
                                                        color: Color.mSecondary
                                                    }
                                                }
                                            }

                                            Text {
                                                width: parent.width
                                                text: itemData.title || ""
                                                font.pixelSize: 13
                                                font.bold: true
                                                color: Color.mOnSurface
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                width: parent.width
                                                text: feedView._alertHeadline(itemData)
                                                font.pixelSize: 10
                                                color: Color.mPrimary
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                width: parent.width
                                                text: feedView._alertSubtitle(itemData)
                                                font.pixelSize: 10
                                                color: Color.mOnSurfaceVariant
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Column {
                                            width: 96
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 8

                                            ActionChip {
                                                width: parent.width
                                                text: "Play Next"
                                                controlHeight: 30
                                                minWidth: parent.width
                                                baseColor: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.18)
                                                hoverColor: Color.mPrimary
                                                activeColor: Color.mPrimary
                                                baseBorderColor: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.38)
                                                hoverBorderColor: Color.mPrimary
                                                activeBorderColor: Color.mPrimary
                                                baseTextColor: Color.mPrimary
                                                hoverTextColor: Color.mOnPrimary
                                                activeTextColor: Color.mOnPrimary
                                                onClicked: feedView.playNextForItem(itemData)
                                            }

                                            ActionChip {
                                                width: parent.width
                                                text: "Open"
                                                controlHeight: 28
                                                minWidth: parent.width
                                                baseColor: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.12)
                                                hoverColor: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.24)
                                                activeColor: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.24)
                                                baseBorderColor: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.28)
                                                hoverBorderColor: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.46)
                                                activeBorderColor: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.46)
                                                baseTextColor: Color.mOnSurface
                                                hoverTextColor: Color.mSecondary
                                                activeTextColor: Color.mSecondary
                                                onClicked: feedView.openEntry(itemData)
                                            }
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 20
                                        color: Color.mPrimary
                                        opacity: alertCardArea.pressed ? 0.08 : (hovered ? 0.04 : 0.0)
                                        Behavior on opacity { NumberAnimation { duration: 130 } }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: upcomingItems.length > 0 ? upcomingColumn.implicitHeight : 0
                        visible: upcomingItems.length > 0

                        Column {
                            id: upcomingColumn
                            width: parent.width
                            spacing: 10

                            Row {
                                width: parent.width
                                spacing: 8

                                Text {
                                    text: "Up Next"
                                    font.pixelSize: 14
                                    font.bold: true
                                    color: Color.mOnSurface
                                }

                                Rectangle {
                                    height: 20
                                    width: upcomingCountText.implicitWidth + 14
                                    radius: 10
                                    color: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.12)
                                    border.width: 1
                                    border.color: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.24)

                                    Text {
                                        id: upcomingCountText
                                        anchors.centerIn: parent
                                        text: upcomingItems.length + " shows"
                                        font.pixelSize: 9
                                        font.bold: true
                                        font.letterSpacing: 0.4
                                        color: Color.mSecondary
                                    }
                                }
                            }

                            Repeater {
                                model: upcomingItems

                                delegate: Rectangle {
                                    readonly property var itemData: modelData
                                    readonly property bool hovered: upcomingCardArea.containsMouse

                                    width: parent.width
                                    height: 92
                                    radius: 20
                                    color: Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.56)
                                    border.width: 1
                                    border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.1)
                                    clip: true

                                    MouseArea {
                                        id: upcomingCardArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: feedView.openEntry(itemData)
                                    }

                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 12

                                        Rectangle {
                                            id: upcomingPoster
                                            width: 56
                                            height: parent.height
                                            radius: 14
                                            color: "transparent"
                                            clip: true
                                             // OpacityMask removed — parent clip: true + radius handles rounding

                                            Image {
                                                anchors.fill: parent
                                                source: itemData.poster || ""
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                cache: true
                                            }
                                        }

                                        Column {
                                            width: parent.width - 56 - 80 - 24
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 5

                                            Row {
                                                spacing: 6

                                                Rectangle {
                                                    height: 18
                                                    width: countdownText.implicitWidth + 10
                                                    radius: 9
                                                    color: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.14)
                                                    border.width: 1
                                                    border.color: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.24)

                                                    Text {
                                                        id: countdownText
                                                        anchors.centerIn: parent
                                                        text: "In " + feedView._timeUntilText(itemData)
                                                        font.pixelSize: 8
                                                        font.bold: true
                                                        color: Color.mSecondary
                                                    }
                                                }

                                                Rectangle {
                                                    visible: String(itemData.feedReason || "").length > 0
                                                    height: 18
                                                    width: upcomingReasonText.implicitWidth + 10
                                                    radius: 9
                                                    color: Qt.rgba(Color.mTertiary.r, Color.mTertiary.g, Color.mTertiary.b, 0.14)
                                                    border.width: 1
                                                    border.color: Qt.rgba(Color.mTertiary.r, Color.mTertiary.g, Color.mTertiary.b, 0.24)

                                                    Text {
                                                        id: upcomingReasonText
                                                        anchors.centerIn: parent
                                                        text: itemData.feedReason || ""
                                                        font.pixelSize: 8
                                                        font.bold: true
                                                        color: Color.mTertiary
                                                    }
                                                }

                                                Rectangle {
                                                    height: 18
                                                    width: upcomingEpisodeText.implicitWidth + 10
                                                    radius: 9
                                                    color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)
                                                    border.width: 1
                                                    border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.22)

                                                    Text {
                                                        id: upcomingEpisodeText
                                                        anchors.centerIn: parent
                                                        text: "Ep " + (itemData.nextEpisode || "?")
                                                        font.pixelSize: 8
                                                        font.bold: true
                                                        color: Color.mPrimary
                                                    }
                                                }
                                            }

                                            Text {
                                                width: parent.width
                                                text: itemData.title || ""
                                                font.pixelSize: 12
                                                font.bold: true
                                                color: Color.mOnSurface
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                width: parent.width
                                                text: feedView._upcomingHeadline(itemData)
                                                font.pixelSize: 10
                                                color: Color.mPrimary
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                width: parent.width
                                                text: feedView._upcomingSubtitle(itemData)
                                                font.pixelSize: 10
                                                color: Color.mOnSurfaceVariant
                                                elide: Text.ElideRight
                                            }
                                        }

                                        ActionChip {
                                            width: 80
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Open"
                                            controlHeight: 30
                                            minWidth: 80
                                            baseColor: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.12)
                                            hoverColor: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.24)
                                            activeColor: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.24)
                                            baseBorderColor: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.28)
                                            hoverBorderColor: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.46)
                                            activeBorderColor: Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.46)
                                            baseTextColor: Color.mOnSurface
                                            hoverTextColor: Color.mSecondary
                                            activeTextColor: Color.mSecondary
                                            onClicked: feedView.openEntry(itemData)
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 20
                                        color: Color.mPrimary
                                        opacity: upcomingCardArea.pressed ? 0.08 : (hovered ? 0.035 : 0.0)
                                        Behavior on opacity { NumberAnimation { duration: 130 } }
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
