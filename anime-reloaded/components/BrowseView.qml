import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
    id: browseView

    property var pluginApi: null
    readonly property var anime: pluginApi?.mainInstance || null
    property int _lastBrowseResetToken: -1

    signal animeSelected(var show)
    signal settingsRequested()

    function _themeColor(name, fallback) {
        var value = Color ? Color[name] : null
        return value !== undefined && value !== null ? value : fallback
    }

    function _withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function _outlineVariantColor() {
        return _themeColor("mOutlineVariant",
            _themeColor("mOutline", Color.mOnSurfaceVariant))
    }

    function _errorContainerColor() {
        return _themeColor("mErrorContainer",
            Qt.tint(Color.mSurface, Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.18)))
    }

    function _onErrorContainerColor() {
        return _themeColor("mOnErrorContainer", Color.mError)
    }

    function _primaryContainerColor() {
        return _themeColor("mPrimaryContainer",
            Qt.tint(Color.mSurface, Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.18)))
    }

    function _onPrimaryContainerColor() {
        return _themeColor("mOnPrimaryContainer", Color.mPrimary)
    }

    function openEntry(entry) {
        browseView.animeSelected({
            id: entry.id,
            name: entry.name,
            englishName: entry.englishName,
            nativeName: entry.nativeName || "",
            thumbnail: entry.thumbnail,
            score: entry.score,
            type: entry.type || "",
            episodeCount: entry.episodeCount || "",
            availableEpisodes: entry.availableEpisodes || { sub: 0, dub: 0, raw: 0 },
            season: entry.season || null,
            providerRefs: entry.providerRefs || ({})
        })
    }

    function resumeEpisodeFor(entry) {
        if (!entry) return ""
        if (entry.lastWatchedEpNum) return entry.lastWatchedEpNum
        var prog = entry.episodeProgress || {}
        var episodes = Object.keys(prog).filter(function(key) {
            return anime?._progressPosition(prog[key]) > 0
        })
        episodes.sort(function(a, b) { return Number(b) - Number(a) })
        return episodes.length > 0 ? episodes[0] : ""
    }

    function resumeProgressRatioFor(entry) {
        var epNum = resumeEpisodeFor(entry)
        if (!entry || !epNum || !anime) return 0
        return anime.getEpisodeProgressRatio(entry.id, epNum)
    }

    function openSearch() {
        searchBar.visible = true
        searchField.forceActiveFocus()
    }

    function toggleSearch() {
        searchBar.visible = !searchBar.visible
        if (searchBar.visible)
            searchField.forceActiveFocus()
        else
            browseView.closeSearch()
    }

    function closeSearch(resetFeed) {
        if (resetFeed === undefined) resetFeed = true
        searchBar.visible = false
        searchField.text = ""
        if (resetFeed && anime) anime.fetchCurrentFeed(true)
    }

    function horizontalWheelDelta(wheel) {
        if (!wheel) return 0
        var dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y
        var dx = wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x : wheel.angleDelta.x
        return Math.abs(dx) > Math.abs(dy) ? dx : dy
    }

    function scrollHorizontally(flickable, wheel) {
        if (!flickable || !wheel) return
        var delta = horizontalWheelDelta(wheel)
        if (delta === 0) return
        var maxX = Math.max(0, flickable.contentWidth - flickable.width)
        flickable.contentX = Math.max(0, Math.min(maxX, flickable.contentX - delta))
        wheel.accepted = true
    }

    function _serialiseBrowseEntry(entry) {
        try {
            return JSON.stringify(entry || {})
        } catch (e) {
            return "{}"
        }
    }

    function _parseBrowseEntry(payload) {
        try {
            return JSON.parse(payload || "{}")
        } catch (e) {
            return ({})
        }
    }

    function _appendBrowseEntries(results, startIndex) {
        var items = results || []
        for (var i = startIndex || 0; i < items.length; i++) {
            var entry = items[i] || ({})
            animeGridModel.append({
                entryId: String(entry.id || ""),
                entryJson: _serialiseBrowseEntry(entry)
            })
        }
    }

    function syncBrowseModel(forceReset) {
        var results = anime?.animeList || []
        var resetToken = anime?.browseResetToken || 0
        var shouldReset = forceReset === true
            || resetToken !== _lastBrowseResetToken
            || results.length < animeGridModel.count

        if (!shouldReset && results.length === animeGridModel.count && animeGridModel.count > 0) {
            var firstId = String((results[0] || {}).id || "")
            var lastId = String((results[results.length - 1] || {}).id || "")
            shouldReset = firstId !== String(animeGridModel.get(0).entryId || "")
                || lastId !== String(animeGridModel.get(animeGridModel.count - 1).entryId || "")
        }

        if (shouldReset) {
            animeGridModel.clear()
            _lastBrowseResetToken = resetToken
            _appendBrowseEntries(results, 0)
            return
        }

        if (results.length > animeGridModel.count)
            _appendBrowseEntries(results, animeGridModel.count)
    }

    onAnimeChanged: {
        _lastBrowseResetToken = anime ? (anime.browseResetToken || 0) : -1
        animeGridModel.clear()
        syncBrowseModel(true)
    }

    ListModel {
        id: animeGridModel
    }

    Connections {
        target: anime
        ignoreUnknownSignals: true

        function onAnimeListChanged() {
            browseView.syncBrowseModel(false)
        }
    }

    TapHandler {
        enabled: searchBar.visible
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: function(eventPoint) {
            var pos = searchBar.mapToItem(browseView, 0, 0)
            var x = eventPoint.position.x
            var y = eventPoint.position.y
            var insideSearchBar =
                x >= pos.x && x <= pos.x + searchBar.width &&
                y >= pos.y && y <= pos.y + searchBar.height
            if (!insideSearchBar)
                browseView.closeSearch()
        }
    }

    // ── Background ────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header ────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 56
            color: "transparent"
            z: 2

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: _outlineVariantColor(); opacity: 0.5
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 18; rightMargin: 10 }
                spacing: 8

                // Wordmark (hidden when search is open)
                Rectangle {
                    id: browseWordmark
                    visible: !searchBar.visible
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 19
                    color: browseTitleArea.containsMouse
                        ? Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.92)
                        : Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.88)
                    border.width: 1
                    border.color: browseTitleArea.containsMouse
                        ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.28)
                        : _withAlpha(_outlineVariantColor(), 0.4)
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Behavior on border.color { ColorAnimation { duration: 180 } }

                    Row {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 14
                        }
                        spacing: 0

                        Text {
                            text: "A"
                            font.pixelSize: 22; font.letterSpacing: 1
                            color: Color.mPrimary
                        }
                        Text {
                            text: "nime"
                            font.pixelSize: 22; font.letterSpacing: 1
                            color: Color.mOnSurface
                            opacity: browseTitleArea.containsMouse ? 1 : 0.85
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                        }
                    }

                    MouseArea {
                        id: browseTitleArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: browseView.openSearch()
                    }
                }

                // Search bar
                Rectangle {
                    id: searchBar
                    Layout.fillWidth: true
                    height: 36; radius: 18
                    color: Color.mSurface
                    visible: false
                    border.color: searchField.activeFocus ? Color.mPrimary : _outlineVariantColor()
                    border.width: searchField.activeFocus ? 1.5 : 1

                    TextInput {
                        id: searchField
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left; right: clearBtn.left
                            leftMargin: 14; rightMargin: 6
                        }
                        color: Color.mOnSurface
                        font.pixelSize: 13
                        clip: true
                        selectByMouse: true
                        onTextChanged: searchDebounce.restart()
                        Keys.onEscapePressed: {
                            browseView.closeSearch()
                        }
                    }

                    Text {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 14 }
                        text: "Search anime…"
                        color: Color.mOnSurfaceVariant
                        font.pixelSize: 13
                        visible: searchField.text.length === 0
                        opacity: 0.6
                    }

                    Item {
                        id: clearBtn
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 10 }
                        width: 22; height: 22
                        visible: searchField.text.length > 0

                        Rectangle {
                            anchors.centerIn: parent
                            width: 18; height: 18; radius: 9
                            color: clearSearchArea.containsMouse ? _primaryContainerColor() : Color.mSurfaceVariant
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: clearSearchArea.containsMouse ? _onPrimaryContainerColor() : Color.mOnSurfaceVariant
                            font.pixelSize: 9; font.bold: true
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        MouseArea {
                            id: clearSearchArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: searchField.text = ""
                        }
                    }
                }

                Timer {
                    id: searchDebounce
                    interval: 350
                    onTriggered: {
                        if (!anime) return
                        if (searchField.text.trim().length > 0)
                            anime.searchAnime(searchField.text.trim(), true)
                        else
                            anime.fetchCurrentFeed(true)
                    }
                }

                // Search toggle
                HoverIconButton {
                    text: "⌕"
                    iconPixelSize: 18
                    selected: searchBar.visible
                    onClicked: browseView.toggleSearch()
                }

                // Sub / Dub toggle
                Rectangle {
                    height: 28
                    width: modeRow.implicitWidth + 16
                    radius: 14
                    color: Color.mSurface
                    border.color: _outlineVariantColor(); border.width: 1

                    Row {
                        id: modeRow
                        anchors.centerIn: parent
                        spacing: 0

                        Repeater {
                            model: ["sub", "dub"]

                            delegate: Item {
                                width: modeLabel.implicitWidth + 16
                                height: 28
                                readonly property bool active: anime?.currentMode === modelData

                                Rectangle {
                                    anchors { fill: parent; margins: 3 }
                                    radius: 11
                                    color: active ? Color.mPrimary : (modeArea.containsMouse ? _primaryContainerColor() : "transparent")
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                }
                                Text {
                                    id: modeLabel
                                    anchors.centerIn: parent
                                    text: modelData.toUpperCase()
                                    font.pixelSize: 10; font.letterSpacing: 1; font.bold: true
                                    color: active ? Color.mOnPrimary : (modeArea.containsMouse ? _onPrimaryContainerColor() : Color.mOnSurfaceVariant)
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                }
                                MouseArea {
                                    id: modeArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: if (anime) anime.setMode(modelData)
                                }
                            }
                        }
                    }
                }

                HoverIconButton {
                    text: "⚙"
                    iconPixelSize: 15
                    onClicked: browseView.settingsRequested()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 44
            color: "transparent"

            Row {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: 18
                }
                spacing: 8

                Repeater {
                    model: [
                        { label: "Top", value: "top" },
                        { label: "Recent", value: "recent" }
                    ]

                    delegate: ChoiceChip {
                        readonly property bool active: (anime?.currentView === modelData.value)
                            || (anime?.currentView === "search" && anime?.browseFeed === modelData.value)
                        text: modelData.label
                        selected: active
                        controlHeight: 30
                        fontPixelSize: 11
                        letterSpacing: 0.4
                        minWidth: 68
                        onClicked: {
                            if (!anime) return
                            browseView.closeSearch(false)
                            if (modelData.value === "recent")
                                anime.fetchRecent(true)
                            else
                                anime.fetchPopular(true)
                        }
                    }
                }
            }
        }

        // ── Genre selector ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            readonly property bool showGenres:
                (anime?.genresList?.length ?? 0) > 0 &&
                ((anime?.browseFeed ?? "top") !== "recent" || (anime?.currentView === "search"))
            height: showGenres ? 56 : 0
            color: "transparent"
            visible: height > 0
            clip: true

            ListView {
                id: genreList
                anchors.fill: parent
                orientation: ListView.Horizontal
                spacing: 8
                leftMargin: 18; rightMargin: 18
                model: ["All"].concat(anime?.genresList || [])
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick

                delegate: ChoiceChip {
                    readonly property bool active: (modelData === "All" && (anime?.currentGenre ?? "") === "") ||
                                                   (anime?.currentGenre === modelData)
                    text: modelData
                    selected: active
                    controlHeight: 32
                    fontPixelSize: 11
                    minWidth: 58
                    onClicked: {
                        if (anime)
                            anime.setGenre(modelData === "All" ? "" : modelData)
                    }
                }

                ScrollBar.horizontal: ScrollBar {
                    policy: ScrollBar.AlwaysOff
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: function(wheel) {
                        browseView.scrollHorizontally(genreList, wheel)
                    }
                }
            }
        }

        // ── Content area ──────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Item {
                    id: continueSection
                    readonly property var continueEntries: anime?.getContinueWatchingList() ?? []
                    readonly property bool showRail: continueEntries.length > 0 && (anime?.currentView ?? "") !== "search"
                    Layout.fillWidth: true
                    Layout.preferredHeight: showRail ? 188 : 0
                    visible: showRail

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Row {
                            width: parent.width
                            spacing: 8

                            Text {
                                text: "Continue Watching"
                                font.pixelSize: 14
                                font.bold: true
                                color: Color.mOnSurface
                            }

                            Rectangle {
                                height: 20
                                width: continueCount.implicitWidth + 14
                                radius: 10
                                color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)
                                border.width: 1
                                border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.28)

                                Text {
                                    id: continueCount
                                    anchors.centerIn: parent
                                    text: continueSection.continueEntries.length + " active"
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.letterSpacing: 0.5
                                    color: Color.mPrimary
                                }
                            }
                        }

                        ListView {
                            id: continueRail
                            width: parent.width
                            height: 148
                            orientation: ListView.Horizontal
                            spacing: 10
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            model: continueSection.continueEntries
                            flickableDirection: Flickable.HorizontalFlick

                            delegate: Item {
                                width: 232
                                height: continueRail.height

                                readonly property var entry: modelData
                                readonly property string resumeEpisode: browseView.resumeEpisodeFor(entry)
                                readonly property real progressRatio: browseView.resumeProgressRatioFor(entry)

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 18
                                    color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.9)
                                    border.width: 1
                                    border.color: _withAlpha(_outlineVariantColor(), 0.38)

                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 10

                                        Rectangle {
                                            width: 72
                                            height: parent.height
                                            radius: 12
                                            clip: true
                                            color: Color.mSurfaceVariant

                                            Image {
                                                anchors.fill: parent
                                                source: entry.thumbnail || ""
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                cache: true
                                            }
                                        }

                                        Column {
                                            width: parent.width - 82
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 6

                                            Rectangle {
                                                height: 20
                                                width: resumeText.implicitWidth + 14
                                                radius: 10
                                                color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)

                                                Text {
                                                    id: resumeText
                                                    anchors.centerIn: parent
                                                    text: resumeEpisode ? "Resume Ep. " + resumeEpisode : "In progress"
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    font.letterSpacing: 0.4
                                                    color: Color.mPrimary
                                                }
                                            }

                                            Text {
                                                width: parent.width
                                                text: entry.englishName || entry.name || ""
                                                font.pixelSize: 13
                                                font.bold: true
                                                color: Color.mOnSurface
                                                wrapMode: Text.Wrap
                                                maximumLineCount: 2
                                                elide: Text.ElideRight
                                                lineHeight: 1.25
                                            }

                                            Text {
                                                width: parent.width
                                                text: (entry.watchedEpisodes || []).length > 0
                                                    ? (entry.watchedEpisodes || []).length + " watched"
                                                    : "Pick up where you left off"
                                                font.pixelSize: 10
                                                color: Color.mOnSurfaceVariant
                                                opacity: 0.78
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                width: parent.width
                                                height: 6
                                                radius: 3
                                                color: _withAlpha(_outlineVariantColor(), 0.26)
                                                visible: progressRatio > 0

                                                Rectangle {
                                                    width: parent.width * progressRatio
                                                    height: parent.height
                                                    radius: parent.radius
                                                    color: Color.mTertiary
                                                }
                                            }

                                            Item { width: 1; height: 2 }

                                            Rectangle {
                                                width: 88
                                                height: 28
                                                radius: 14
                                                z: 3
                                                readonly property bool hovered: continueButtonArea.containsMouse
                                                color: hovered
                                                    ? Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.28)
                                                    : Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.18)
                                                border.width: 1
                                                border.color: hovered
                                                    ? Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.58)
                                                    : Qt.rgba(Color.mSecondary.r, Color.mSecondary.g, Color.mSecondary.b, 0.42)
                                                Behavior on color { ColorAnimation { duration: 140 } }
                                                Behavior on border.color { ColorAnimation { duration: 140 } }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Open"
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                    font.letterSpacing: 0.5
                                                    color: Color.mSecondary
                                                    Behavior on color { ColorAnimation { duration: 140 } }
                                                }

                                                MouseArea {
                                                    id: continueButtonArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: browseView.openEntry(entry)
                                                }

                                                StyledToolTip {
                                                    target: continueButtonArea
                                                    shown: continueButtonArea.containsMouse
                                                    above: true
                                                    text: "Open details"
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        z: 1
                                        hoverEnabled: false
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: browseView.openEntry(entry)
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.NoButton
                                onWheel: function(wheel) {
                                    browseView.scrollHorizontally(continueRail, wheel)
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Loading
                    Rectangle {
                        anchors.fill: parent; color: "transparent"
                        visible: (anime?.isFetchingAnime ?? false) && animeGridModel.count === 0
                        z: 10

                        Column {
                            anchors.centerIn: parent; spacing: 14

                            Rectangle {
                                width: 34; height: 34; radius: 17
                                anchors.horizontalCenter: parent.horizontalCenter
                                color: "transparent"
                                border.color: Color.mPrimary; border.width: 2.5
                                RotationAnimator on rotation {
                                    from: 0; to: 360; duration: 800
                                    loops: Animation.Infinite; running: parent.visible
                                    easing.type: Easing.Linear
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "loading"
                                color: Color.mOnSurfaceVariant
                                font.pixelSize: 11; font.letterSpacing: 2.5; opacity: 0.7
                            }
                        }
                    }

                    // Error
                    Rectangle {
                        anchors.fill: parent; color: "transparent"
                        visible: (anime?.animeError?.length ?? 0) > 0 && !(anime?.isFetchingAnime ?? false)
                        z: 9

                        Column {
                            anchors.centerIn: parent; spacing: 10

                            Text {
                                text: "⚠"; font.pixelSize: 30; color: Color.mError
                                anchors.horizontalCenter: parent.horizontalCenter; opacity: 0.8
                            }
                            Text {
                                text: anime?.animeError ?? ""
                                color: Color.mOnSurfaceVariant; font.pixelSize: 12
                                wrapMode: Text.Wrap; width: 280
                                horizontalAlignment: Text.AlignHCenter; lineHeight: 1.4
                            }
                        }
                    }

                    // Grid
                    GridView {
                        id: animeGrid
                        anchors.fill: parent; anchors.margins: 10
                        
                        readonly property var columnsMap: ({ "small": 8, "medium": 5, "large": 3 })
                        readonly property int columns: columnsMap[anime?.posterSize || "medium"]
                        property real lastStableContentY: 0
                        property real lastContentHeight: 0
                        property bool preserveScrollOnAppend: false
                        
                        cellWidth: (width - 10) / columns
                        cellHeight: cellWidth * 1.58
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: animeGridModel

                        function requestNextPage() {
                            if (!anime || anime.isFetchingAnime)
                                return
                            preserveScrollOnAppend = true
                            lastStableContentY = Math.max(lastStableContentY, contentY)
                            anime.fetchNextPage()
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            contentItem: Rectangle {
                                implicitWidth: 3; color: Color.mPrimary; opacity: 0.45; radius: 2
                            }
                        }

                        onContentYChanged: {
                            var transientReset = preserveScrollOnAppend
                                && (anime?.isFetchingAnime ?? false)
                                && contentY <= 0
                                && lastStableContentY > 0
                            if (!transientReset)
                                lastStableContentY = Math.max(lastStableContentY, contentY)
                            if (anime && !transientReset)
                                anime.setBrowseScroll(contentY)
                            if (contentY + height > contentHeight - cellHeight * 2)
                                requestNextPage()
                        }

                        onVisibleChanged: {
                            if (!visible || !anime) return
                            preserveScrollOnAppend = false
                            lastStableContentY = anime.browseScrollY || 0
                            Qt.callLater(function() {
                                animeGrid.contentY = Math.min(
                                    anime.browseScrollY || 0,
                                    Math.max(0, animeGrid.contentHeight - animeGrid.height)
                                )
                            })
                        }

                        onContentHeightChanged: {
                            if (preserveScrollOnAppend && contentHeight > lastContentHeight) {
                                var targetY = Math.min(
                                    lastStableContentY,
                                    Math.max(0, contentHeight - height)
                                )
                                if (animeGrid.contentY + 2 < targetY) {
                                    Qt.callLater(function() {
                                        animeGrid.contentY = targetY
                                        if (anime)
                                            anime.setBrowseScroll(targetY)
                                    })
                                }
                                preserveScrollOnAppend = false
                            }
                            lastContentHeight = contentHeight
                        }

                        delegate: Item {
                            width: animeGrid.cellWidth
                            height: animeGrid.cellHeight
                            readonly property var entry: browseView._parseBrowseEntry(entryJson)

                            readonly property bool inLibrary: {
                                var _ = anime?.libraryVersion ?? 0
                                return anime?.isInLibrary(entryId) ?? false
                            }
                            readonly property bool cardHovered: cardArea.containsMouse || libraryActionArea.containsMouse
                            readonly property bool showLibraryAction: inLibrary || cardHovered
                            readonly property bool actionIsRemove: inLibrary && cardHovered

                            Rectangle {
                                id: card
                                anchors { fill: parent; margins: 5 }
                                radius: 10; color: Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.45)
                                clip: true

                                // Title bar (defined before wrapper so it can be referenced if needed)
                                Rectangle {
                                    id: titleBar
                                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                    height: titleText.implicitHeight + 14
                                    color: Color.mSurfaceVariant; radius: 10

                                    Text {
                                        id: titleText
                                        anchors {
                                            left: parent.left; right: parent.right
                                            verticalCenter: parent.verticalCenter
                                            leftMargin: 8; rightMargin: 8
                                        }
                                        text: entry.englishName || entry.name || ""
                                        font.pixelSize: 10; font.letterSpacing: 0.2
                                        color: Color.mOnSurface
                                        wrapMode: Text.Wrap; maximumLineCount: 2
                                        elide: Text.ElideRight; lineHeight: 1.3
                                    }
                                }

                                // Poster Wrapper
                                Rectangle {
                                    id: posterWrapper
                                    anchors { top: parent.top; left: parent.left; right: parent.right; bottom: titleBar.top }
                                    radius: 10; clip: true; color: "transparent"
                                        // OpacityMask removed (was from Qt5Compat.GraphicalEffects)
                                    // Parent Rectangle already has clip: true + radius for rounded corners

                                    Image {
                                        id: coverImg
                                        anchors.fill: parent
                                        source: entry.thumbnail || ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true; cache: true
                                        opacity: status === Image.Ready ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 300 } }

                                        Rectangle {
                                            anchors.fill: parent; color: Color.mSurfaceVariant
                                            visible: coverImg.status !== Image.Ready
                                            Text {
                                                anchors.centerIn: parent; text: "◫"
                                                font.pixelSize: 28; color: Color.mOutline; opacity: 0.25
                                            }
                                        }

                                        // Score badge
                                        Rectangle {
                                            visible: entry.score != null
                                            anchors { top: parent.top; left: parent.left; topMargin: 6; leftMargin: 6 }
                                            height: 18; radius: 9
                                            width: scoreText.implicitWidth + 10
                                            color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.88)
                                            border.width: 1
                                            border.color: _withAlpha(_outlineVariantColor(), 0.38)

                                            Text {
                                                id: scoreText; anchors.centerIn: parent
                                                text: entry.score != null ? "★ " + (entry.score || 0).toFixed(1) : ""
                                                font.pixelSize: 8; font.bold: true; font.letterSpacing: 0.5
                                                color: Color.mPrimary
                                            }
                                        }

                                        // Type badge
                                        Rectangle {
                                            visible: (entry.type || "").length > 0
                                            anchors { top: parent.top; right: parent.right; topMargin: 6; rightMargin: 6 }
                                            height: 18; radius: 9
                                            width: typeText.implicitWidth + 10
                                            color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.86)
                                            border.width: 1
                                            border.color: _withAlpha(_outlineVariantColor(), 0.36)

                                            Text {
                                                id: typeText; anchors.centerIn: parent
                                                text: (entry.type || "").toUpperCase()
                                                font.pixelSize: 8; font.letterSpacing: 1; font.bold: true
                                                color: Color.mPrimary
                                            }
                                        }

                                        // Episode count badge
                                        Rectangle {
                                            readonly property int displayEpisodeCount: {
                                                var avail = entry.availableEpisodes || ({})
                                                var modeCount = (anime?.currentMode === "dub")
                                                    ? (avail.dub || 0)
                                                    : (avail.sub || 0)
                                                var fallback = Math.max(
                                                    modeCount,
                                                    avail.sub || 0,
                                                    avail.dub || 0,
                                                    avail.raw || 0,
                                                    Number(entry.episodeCount || 0)
                                                )
                                                return fallback
                                            }
                                            visible: displayEpisodeCount > 0
                                            anchors {
                                                bottom: parent.bottom; right: parent.right
                                                bottomMargin: 6; rightMargin: 6
                                            }
                                            height: 18; radius: 9
                                            width: epText.implicitWidth + 10
                                            color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.88)
                                            border.width: 1
                                            border.color: _withAlpha(_outlineVariantColor(), 0.38)

                                            Text {
                                                id: epText; anchors.centerIn: parent
                                                text: parent.displayEpisodeCount + " ep"
                                                font.pixelSize: 8; font.letterSpacing: 0.5
                                                color: Color.mOnSurface
                                            }
                                        }

                                        // Gradient
                                        Rectangle {
                                            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                            height: 40
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: "transparent" }
                                                GradientStop { position: 1.0; color: Color.mSurfaceVariant }
                                            }
                                        }
                                    }
                                }

                                // Library action
                                Rectangle {
                                    id: libraryAction
                                    anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 8 }
                                    width: 32
                                    height: 32
                                    radius: 16
                                    opacity: showLibraryAction ? 1 : 0
                                    scale: showLibraryAction ? 1 : 0.82
                                    visible: opacity > 0
                                    color: inLibrary
                                        ? (actionIsRemove
                                            ? _withAlpha(_errorContainerColor(), 0.96)
                                            : Color.mPrimary)
                                        : Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.92)
                                    border.width: 1
                                    border.color: inLibrary
                                        ? (actionIsRemove ? Color.mError : Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.6))
                                        : _withAlpha(_outlineVariantColor(), 0.42)
                                    z: 3

                                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    Behavior on border.color { ColorAnimation { duration: 140 } }

                                    NIcon {
                                        id: bookmarkIcon
                                        anchors.centerIn: parent
                                        icon: "bookmark"
                                        pointSize: 14
                                        color: Color.mOnPrimary
                                        opacity: inLibrary && !actionIsRemove ? 1 : 0
                                        scale: inLibrary && !actionIsRemove ? 1 : 0.7
                                        Behavior on opacity { NumberAnimation { duration: 110 } }
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                    }

                                    Text {
                                        id: addIcon
                                        anchors.centerIn: parent
                                        text: "+"
                                        font.pixelSize: 18
                                        font.bold: true
                                        color: Color.mPrimary
                                        opacity: !inLibrary && cardHovered ? 1 : 0
                                        scale: !inLibrary && cardHovered ? 1 : 0.7
                                        Behavior on opacity { NumberAnimation { duration: 110 } }
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                    }

                                    Text {
                                        id: removeIcon
                                        anchors.centerIn: parent
                                        text: "−"
                                        font.pixelSize: 18
                                        font.bold: true
                                        color: _onErrorContainerColor()
                                        opacity: actionIsRemove ? 1 : 0
                                        scale: actionIsRemove ? 1 : 0.7
                                        Behavior on opacity { NumberAnimation { duration: 110 } }
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                    }

                                    MouseArea {
                                        id: libraryActionArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        acceptedButtons: Qt.LeftButton
                                        onClicked: {
                                            if (!anime) return
                                            if (inLibrary)
                                                anime.removeFromLibrary(entryId)
                                            else
                                                anime.addToLibrary(entry)
                                        }
                                    }
                                }

                                // Hover/press overlay
                                Rectangle {
                                    anchors.fill: parent; radius: 10; color: Color.mPrimary
                                    opacity: cardArea.pressed ? 0.16 : (cardArea.containsMouse ? 0.07 : 0)
                                    Behavior on opacity { NumberAnimation { duration: 130 } }
                                }

                                transform: Scale {
                                    origin.x: card.width / 2; origin.y: card.height / 2
                                    xScale: cardArea.pressed ? 0.97 : 1.0
                                    yScale: cardArea.pressed ? 0.97 : 1.0
                                    Behavior on xScale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    Behavior on yScale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                }

                                MouseArea {
                                    id: cardArea
                                    anchors.fill: parent; hoverEnabled: true
                                    onClicked: browseView.openEntry(entry)
                                }

                                StyledToolTip {
                                    target: libraryActionArea
                                    shown: libraryActionArea.containsMouse
                                    above: false
                                    text: inLibrary ? "Remove from library" : "Add to library"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
