import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
    id: detailView

    property var pluginApi: null
    readonly property var anime: pluginApi?.mainInstance || null
    property string _lastCenteredEpisodeKey: ""

    signal backRequested()

    readonly property bool _inLibrary:
        anime && anime.currentAnime ? anime.isInLibrary(anime.currentAnime.id) : false
    readonly property var _nextEpisode:
        anime?.currentAnime ? anime.getNextUnwatchedEpisode(anime.currentAnime) : null
    property string _lastCenteredSeasonKey: ""

    function centerPreferredEpisode(force) {
        if (!anime?.currentAnime || !epList.visible) return

        var entry = anime.getLibraryEntry(anime.currentAnime.id)
        var lastEpNum = entry?.lastWatchedEpNum || ""
        var targetEpNum = anime?.detailFocusEpisodeNum || ""
        var episodes = anime.currentAnime.episodes || []
        if ((!lastEpNum && !targetEpNum) || episodes.length === 0) return

        var focusEpNum = targetEpNum || lastEpNum
        var key = String(anime.currentAnime.id || "") + ":" + String(focusEpNum) + ":" + String(episodes.length)
        if (!force && _lastCenteredEpisodeKey === key)
            return

        var index = -1
        for (var i = 0; i < episodes.length; i++) {
            if (String(episodes[i].number) === String(focusEpNum)) {
                index = i
                break
            }
        }
        if (index < 0) return

        _lastCenteredEpisodeKey = key
        Qt.callLater(function() {
            if (!epList.visible || epList.count <= index) return
            epList.positionViewAtIndex(index, ListView.Center)
        })
    }

    function _streamTitle() {
        return anime?.currentAnime
            ? (anime.currentAnime.englishName || anime.currentAnime.name || "")
            : ""
    }

    function _seasonEntries() {
        return anime?.currentAnime?.seasonEntries || []
    }

    function _seasonMetaText(item) {
        if (!item) return ""
        var season = item.season || ({})
        var parts = []
        if (season.quarter)
            parts.push(season.quarter)
        if (season.year)
            parts.push(String(season.year))
        if (item.type)
            parts.push(String(item.type))
        return parts.join(" · ")
    }

    function openSeason(item) {
        if (!anime || !item || !item.id) return
        var currentMetadataId = String(anime?.currentAnime?.providerRefs?.metadata?.id
            || anime?.currentAnime?.id || "")
        if (String(item.id) === currentMetadataId)
            return
        anime.fetchAnimeDetail({
            id: item.id,
            name: item.name || "",
            englishName: item.englishName || "",
            nativeName: item.nativeName || "",
            thumbnail: item.thumbnail || "",
            type: item.type || "",
            season: item.season || null,
            providerRefs: item.providerRefs || ({
                metadata: { provider: "anilist", id: String(item.id) }
            })
        })
    }

    function centerCurrentSeason(force) {
        if (!seasonList.visible) return
        var seasons = detailView._seasonEntries()
        if (!seasons || seasons.length <= 1) return
        var currentMetadataId = String(anime?.currentAnime?.providerRefs?.metadata?.id
            || anime?.currentAnime?.id || "")
        var key = currentMetadataId + ":" + String(seasons.length)
        if (!force && _lastCenteredSeasonKey === key)
            return

        var index = -1
        for (var i = 0; i < seasons.length; i++) {
            if (String(seasons[i].id || "") === currentMetadataId) {
                index = i
                break
            }
        }
        if (index < 0) return

        _lastCenteredSeasonKey = key
        Qt.callLater(function() {
            if (!seasonList.visible || seasonList.count <= index) return
            seasonList.positionViewAtIndex(index, ListView.Center)
        })
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

    function _themeColor(name, fallback) {
        var value = Color ? Color[name] : null
        return value !== undefined && value !== null ? value : fallback
    }

    function _withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function _surfaceColor() {
        return _themeColor("mSurface", Qt.rgba(0.11, 0.12, 0.14, 1))
    }

    function _surfaceVariantColor() {
        return _themeColor("mSurfaceVariant",
            Qt.tint(_surfaceColor(), Qt.rgba(1, 1, 1, 0.06)))
    }

    function _primaryColor() {
        return _themeColor("mPrimary", Qt.rgba(0.53, 0.65, 0.96, 1))
    }

    function _onPrimaryColor() {
        return _themeColor("mOnPrimary", Qt.rgba(0.06, 0.08, 0.12, 1))
    }

    function _errorColor() {
        return _themeColor("mError", Qt.rgba(0.91, 0.34, 0.33, 1))
    }

    function _tertiaryColor() {
        return _themeColor("mTertiary", Qt.rgba(0.42, 0.82, 0.75, 1))
    }

    function _onSurfaceVariantColor() {
        return _themeColor("mOnSurfaceVariant",
            _themeColor("mOnSurface", Qt.rgba(0.92, 0.94, 0.97, 0.84)))
    }

    function _outlineColor() {
        return _themeColor("mOutline", _onSurfaceVariantColor())
    }

    function _outlineVariantColor() {
        return _themeColor("mOutlineVariant", _outlineColor())
    }

    function _primaryContainerColor() {
        return _themeColor("mPrimaryContainer",
            Qt.tint(_surfaceColor(), _withAlpha(_primaryColor(), 0.18)))
    }

    function _onPrimaryContainerColor() {
        return _themeColor("mOnPrimaryContainer", _primaryColor())
    }

    function _errorContainerColor() {
        return _themeColor("mErrorContainer",
            Qt.tint(_surfaceColor(), _withAlpha(_errorColor(), 0.18)))
    }

    function _onErrorContainerColor() {
        return _themeColor("mOnErrorContainer", _errorColor())
    }

    component SeasonChipLabel: Item {
        id: seasonChipLabel

        property string text: ""
        property color textColor: Color.mOnSurface
        property real pixelSize: 11
        property bool bold: false
        property real textOpacity: 1
        property bool activeScroll: false
        property real gap: 18

        readonly property bool canScroll:
            activeScroll && primaryLabel.implicitWidth > width + 1
        readonly property real travelDistance:
            canScroll ? primaryLabel.implicitWidth + gap : 0

        implicitHeight: primaryLabel.implicitHeight
        clip: true

        onCanScrollChanged: {
            if (!canScroll)
                labelTrack.x = 0
        }

        Row {
            id: labelTrack
            x: 0
            spacing: seasonChipLabel.gap

            Text {
                id: primaryLabel
                text: seasonChipLabel.text
                font.pixelSize: seasonChipLabel.pixelSize
                font.bold: seasonChipLabel.bold
                color: seasonChipLabel.textColor
                opacity: seasonChipLabel.textOpacity
                elide: seasonChipLabel.canScroll ? Text.ElideNone : Text.ElideRight
                Behavior on color { ColorAnimation { duration: 140 } }
            }

            Text {
                visible: seasonChipLabel.canScroll
                text: seasonChipLabel.text
                font.pixelSize: seasonChipLabel.pixelSize
                font.bold: seasonChipLabel.bold
                color: seasonChipLabel.textColor
                opacity: seasonChipLabel.textOpacity
                elide: Text.ElideNone
                Behavior on color { ColorAnimation { duration: 140 } }
            }
        }

        SequentialAnimation {
            id: marqueeAnimation
            running: seasonChipLabel.canScroll
            loops: Animation.Infinite

            PauseAnimation { duration: 500 }

            NumberAnimation {
                target: labelTrack
                property: "x"
                from: 0
                to: -seasonChipLabel.travelDistance
                duration: Math.max(2200, seasonChipLabel.travelDistance * 38)
                easing.type: Easing.InOutQuad
            }

            PauseAnimation { duration: 350 }

            PropertyAction {
                target: labelTrack
                property: "x"
                value: 0
            }
        }
    }

    function _malBadgeFill(badge) {
        var tone = String(badge?.tone || "")
        var base = _withAlpha(_surfaceColor(), 0.94)
        if (tone === "error")
            return Qt.tint(base, _withAlpha(_errorColor(), 0.18))
        if (tone === "accent")
            return Qt.tint(base, _withAlpha(_tertiaryColor(), 0.18))
        if (tone === "primary")
            return Qt.tint(base, _withAlpha(_primaryColor(), 0.18))
        return _withAlpha(_surfaceColor(), 0.92)
    }

    function _malBadgeBorder(badge) {
        var tone = String(badge?.tone || "")
        if (tone === "error")
            return _withAlpha(_errorColor(), 0.34)
        if (tone === "accent")
            return _withAlpha(_tertiaryColor(), 0.34)
        if (tone === "primary")
            return _withAlpha(_primaryColor(), 0.34)
        return _withAlpha(_outlineVariantColor(), 0.36)
    }

    function _malBadgeTextColor(badge) {
        var tone = String(badge?.tone || "")
        if (tone === "error")
            return _errorColor()
        if (tone === "accent")
            return _tertiaryColor()
        if (tone === "primary")
            return _primaryColor()
        return _onSurfaceVariantColor()
    }

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
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                spacing: 8

                // Back button
                HoverIconButton {
                    text: "←"
                    iconPixelSize: 18
                    onClicked: detailView.backRequested()
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 19
                    color: _withAlpha(_surfaceColor(), 0.88)
                    border.width: 1
                    border.color: _withAlpha(_outlineVariantColor(), 0.4)

                    Text {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 14
                            rightMargin: 14
                        }
                        text: anime?.currentAnime
                            ? (anime.currentAnime.englishName || anime.currentAnime.name || "")
                            : ""
                        font.pixelSize: 13
                        color: Color.mOnSurface
                        elide: Text.ElideRight
                    }
                }

                // Library button
                ActionChip {
                    visible: anime?.currentAnime != null && detailView._nextEpisode != null
                    text: detailView._nextEpisode
                        ? "Next Ep. " + detailView._nextEpisode.number
                        : "Next"
                    leadingText: "▶"
                    fontPixelSize: 11
                    letterSpacing: 0.3
                    boldLabel: false
                    horizontalPadding: 17
                    controlHeight: 32
                    onClicked: {
                        if (!anime?.currentAnime) return
                        anime.playNextUnwatched(anime.currentAnime)
                    }
                }

                ActionChip {
                    visible: anime?.currentAnime != null
                    text: "Library"
                    leadingText: detailView._inLibrary ? "✓" : "+"
                    fontPixelSize: 11
                    letterSpacing: 0.3
                    boldLabel: false
                    horizontalPadding: 14
                    controlHeight: 32
                    active: detailView._inLibrary
                    activeColor: detailView._primaryContainerColor()
                    activeHoverColor: Color.mPrimary
                    activeTextColor: detailView._onPrimaryContainerColor()
                    activeHoverTextColor: Color.mOnPrimary
                    onClicked: {
                        if (!anime?.currentAnime) return
                        if (detailView._inLibrary)
                            anime.removeFromLibrary(anime.currentAnime.id)
                        else
                            anime.addToLibrary(anime.currentAnime)
                    }
                }
            }
        }

        // ── Episode count / last watched sub-bar ──────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            readonly property real metaContentHeight:
                detailMetaFlow.implicitHeight
            height: Math.max(30, metaContentHeight + 10)
            color: "transparent"
            visible: anime?.currentAnime != null

            Item {
                anchors.fill: parent
                anchors.margins: 5
                anchors.leftMargin: 16
                anchors.rightMargin: 16

                readonly property var libraryEntry: anime?.currentAnime
                    ? anime.getLibraryEntry(anime.currentAnime.id) : null
                readonly property var episodeList: anime?.currentAnime?.episodes || []
                readonly property var watchAction: anime?.currentAnime
                    ? anime.getShowWatchAction(anime.currentAnime) : null
                readonly property var malBadge: anime?.currentAnime
                    ? anime.malSyncBadge(anime.currentAnime, false)
                    : ({ visible: false, label: "", detail: "", tone: "muted" })
                readonly property int lastWatchedIndex: {
                    if (!libraryEntry || !episodeList.length) return -1
                    for (var i = 0; i < episodeList.length; i++) {
                        if (String(episodeList[i].number) === String(libraryEntry.lastWatchedEpNum))
                            return i
                    }
                    return -1
                }
                readonly property bool hasOlderUnwatched: {
                    if (!libraryEntry || lastWatchedIndex < 0) return false
                    for (var i = 0; i <= lastWatchedIndex; i++) {
                        if (!(anime?.isEpisodeWatched(anime?.currentAnime?.id ?? "", episodeList[i].number) ?? false))
                            return true
                    }
                    return false
                }
                readonly property bool canApplyWatchAction:
                    watchAction !== null && watchAction !== undefined && !watchAction.isComplete

                Flow {
                    id: detailMetaFlow
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        topMargin: 0
                    }
                    spacing: 8

                    Text {
                        text: {
                            var eps = anime?.currentAnime?.episodes
                            return eps ? (eps.length + " episodes") : ""
                        }
                        font.pixelSize: 11
                        font.letterSpacing: 1
                        color: Color.mOnSurfaceVariant
                        opacity: 0.75
                        verticalAlignment: Text.AlignVCenter
                    }

                    Rectangle {
                        visible: parent.parent.libraryEntry !== null && parent.parent.libraryEntry !== undefined
                            && (parent.parent.libraryEntry.lastWatchedEpNum || "") !== ""
                        height: 20
                        width: lastWatchedText.implicitWidth + 18
                        radius: 10
                        color: detailView._withAlpha(detailView._primaryColor(), 0.12)
                        border.color: detailView._primaryColor()
                        border.width: 1

                        Text {
                            id: lastWatchedText
                            anchors.centerIn: parent
                            text: parent.visible ? "Last: Ep. " + detailMetaFlow.parent.libraryEntry.lastWatchedEpNum : ""
                            font.pixelSize: 9
                            font.letterSpacing: 0.8
                            color: detailView._primaryColor()
                        }
                    }

                    ActionChip {
                        visible: detailMetaFlow.parent.watchAction !== null && detailMetaFlow.parent.watchAction !== undefined
                        text: detailMetaFlow.parent.watchAction?.label || ""
                        enabled: detailMetaFlow.parent.canApplyWatchAction
                        disabledOpacity: detailMetaFlow.parent.watchAction?.isComplete ? 0.92 : 0.45
                        active: detailMetaFlow.parent.watchAction?.isComplete || false
                        activeColor: detailView._primaryContainerColor()
                        activeHoverColor: detailView._primaryContainerColor()
                        activeTextColor: detailView._onPrimaryContainerColor()
                        activeHoverTextColor: detailView._onPrimaryContainerColor()
                        controlHeight: 22
                        horizontalPadding: 11
                        fontPixelSize: 9
                        letterSpacing: 0.6
                        onClicked: {
                            if (!anime?.currentAnime) return
                            anime.applyShowWatchAction(anime.currentAnime)
                        }
                    }

                    ActionChip {
                        visible: detailMetaFlow.parent.hasOlderUnwatched
                        text: "Mark 1→Last"
                        controlHeight: 22
                        horizontalPadding: 11
                        fontPixelSize: 9
                        letterSpacing: 0.6
                        onClicked: {
                            if (!anime?.currentAnime || !detailMetaFlow.parent.libraryEntry) return
                            anime.markEpisodesThrough(
                                anime.currentAnime,
                                detailMetaFlow.parent.libraryEntry.lastWatchedEpId || "",
                                detailMetaFlow.parent.libraryEntry.lastWatchedEpNum || "",
                                detailMetaFlow.parent.lastWatchedIndex
                            )
                        }
                    }

                    Rectangle {
                        visible: detailMetaFlow.parent.malBadge?.visible ?? false
                        height: 20
                        width: malBadgeText.implicitWidth + 18
                        radius: 10
                        color: detailView._malBadgeFill(detailMetaFlow.parent.malBadge)
                        border.color: detailView._malBadgeBorder(detailMetaFlow.parent.malBadge)
                        border.width: 1

                        Text {
                            id: malBadgeText
                            anchors.centerIn: parent
                            text: detailMetaFlow.parent.malBadge?.label || ""
                            font.pixelSize: 9
                            font.bold: true
                            font.letterSpacing: 0.8
                            color: detailView._malBadgeTextColor(detailMetaFlow.parent.malBadge)
                        }

                        MouseArea {
                            id: malBadgeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }

                        StyledToolTip {
                            target: malBadgeArea
                            shown: malBadgeArea.containsMouse
                            above: false
                            text: detailMetaFlow.parent.malBadge?.detail || ""
                        }
                    }

                    ActionChip {
                        visible: (anime?.malSync?.enabled ?? false)
                            && anime?.currentAnime != null
                            && String(anime?._showMalId(anime.currentAnime) || "").length > 0
                        text: "Remove MAL"
                        controlHeight: 22
                        horizontalPadding: 11
                        fontPixelSize: 9
                        letterSpacing: 0.6
                        baseColor: detailView._withAlpha(detailView._errorColor(), 0.1)
                        hoverColor: detailView._withAlpha(detailView._errorColor(), 0.18)
                        activeColor: detailView._withAlpha(detailView._errorColor(), 0.18)
                        baseBorderColor: detailView._withAlpha(detailView._errorColor(), 0.24)
                        hoverBorderColor: detailView._withAlpha(detailView._errorColor(), 0.42)
                        activeBorderColor: detailView._withAlpha(detailView._errorColor(), 0.42)
                        baseTextColor: detailView._errorColor()
                        hoverTextColor: detailView._errorColor()
                        activeTextColor: detailView._errorColor()
                        activeHoverTextColor: detailView._errorColor()
                        onClicked: {
                            if (!anime?.currentAnime) return
                            anime.removeShowFromMal(anime.currentAnime, true)
                        }
                    }

                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: _outlineVariantColor(); opacity: 0.3
            }
        }

        // ── Hero: thumbnail + description ─────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 160
            color: _withAlpha(_surfaceColor(), 0.36)
            clip: true
            visible: anime?.currentAnime != null

            // Blurred background from thumbnail
            Image {
                anchors.fill: parent
                source: anime?.currentAnime?.thumbnail ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: 0.15
                layer.enabled: true
                layer.effect: null
            }

            // Dark gradient overlay
            Rectangle {
                anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: detailView._withAlpha(detailView._surfaceVariantColor(), 0.22) }
                    GradientStop { position: 1.0; color: detailView._withAlpha(detailView._surfaceColor(), 0.35) }
                }
            }

            Row {
                anchors { fill: parent; margins: 12 }
                spacing: 12

                // Thumbnail
                Rectangle {
                    width: 100; height: 136
                    radius: 8; clip: true
                    color: Color.mSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        anchors.fill: parent
                        source: anime?.currentAnime?.thumbnail ?? ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                }

                // Description
                Item {
                    width: parent.width - 124
                    height: parent.height
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors { fill: parent; topMargin: 4 }
                        text: anime?.currentAnime?.description ?? ""
                        color: Color.mOnSurface
                        font.pixelSize: 11
                        lineHeight: 1.4
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: 8
                        opacity: 0.85
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: _outlineVariantColor(); opacity: 0.3
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: detailView._seasonEntries().length > 1
            height: visible ? 92 : 0
            color: _withAlpha(_surfaceColor(), 0.54)

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                Text {
                    text: "Seasons"
                    font.pixelSize: 11
                    font.letterSpacing: 1.2
                    color: Color.mOnSurfaceVariant
                    opacity: 0.82
                }

                ListView {
                    id: seasonList
                    width: parent.width
                    height: 48
                    orientation: ListView.Horizontal
                    spacing: 8
                    clip: true
                    model: detailView._seasonEntries()
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    onModelChanged: detailView.centerCurrentSeason(false)
                    onVisibleChanged: if (visible) detailView.centerCurrentSeason(true)

                    delegate: Rectangle {
                        readonly property bool isCurrent:
                            String(modelData.id || "") === String(anime?.currentAnime?.providerRefs?.metadata?.id
                                || anime?.currentAnime?.id || "")
                        readonly property bool hovered: seasonHover.hovered
                        width: 168
                        height: 48
                        radius: 14
                        color: isCurrent
                            ? detailView._primaryColor()
                            : (hovered
                                ? detailView._withAlpha(detailView._primaryColor(), 0.18)
                                : detailView._withAlpha(detailView._surfaceVariantColor(), 0.82))
                        border.width: 1
                        border.color: isCurrent
                            ? detailView._primaryColor()
                            : (hovered
                                ? detailView._withAlpha(detailView._primaryColor(), 0.45)
                                : detailView._withAlpha(detailView._primaryColor(), 0.28))
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on border.color { ColorAnimation { duration: 140 } }

                        Column {
                            anchors.fill: parent
                            anchors.margins: 9
                            spacing: 2

                            SeasonChipLabel {
                                width: parent.width
                                text: modelData.englishName || modelData.name || ""
                                pixelSize: 11
                                bold: isCurrent
                                activeScroll: hovered
                                textColor: isCurrent
                                    ? detailView._onPrimaryColor()
                                    : (hovered ? detailView._primaryColor() : Color.mOnSurface)
                            }

                            SeasonChipLabel {
                                width: parent.width
                                readonly property string seasonMetaText: detailView._seasonMetaText(modelData)
                                text: isCurrent
                                    ? (seasonMetaText.length > 0 ? "Current · " + seasonMetaText : "Current")
                                    : seasonMetaText
                                pixelSize: 9
                                activeScroll: hovered
                                textColor: isCurrent
                                    ? detailView._onPrimaryColor()
                                    : (hovered ? detailView._primaryColor() : detailView._onSurfaceVariantColor())
                                textOpacity: 0.8
                            }
                        }

                        HoverHandler { id: seasonHover }

                        MouseArea {
                            id: seasonArea
                            anchors.fill: parent
                            enabled: !parent.isCurrent
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: detailView.openSeason(modelData)
                        }
                    }

                    ScrollBar.horizontal: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: function(wheel) {
                            detailView.scrollHorizontally(seasonList, wheel)
                        }
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: _outlineVariantColor(); opacity: 0.25
            }
        }

        // ── Episode list ──────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            // Fetching detail spinner
            Rectangle {
                anchors.fill: parent; color: "transparent"
                visible: anime?.isFetchingDetail ?? false; z: 5

                Column {
                    anchors.centerIn: parent; spacing: 14

                    Rectangle {
                        width: 28; height: 28; radius: 14
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: "transparent"; border.color: Color.mPrimary; border.width: 2
                        RotationAnimator on rotation {
                            from: 0; to: 360; duration: 800
                            loops: Animation.Infinite; running: parent.visible
                            easing.type: Easing.Linear
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "fetching episodes"
                        color: Color.mOnSurfaceVariant
                        font.pixelSize: 11; font.letterSpacing: 2; opacity: 0.7
                    }
                }
            }

            // Fetching stream spinner
            Rectangle {
                anchors.fill: parent
                color: detailView._withAlpha(detailView._surfaceColor(), 0.68)
                visible: anime?.isFetchingLinks ?? false; z: 6

                Column {
                    anchors.centerIn: parent; spacing: 14

                    Rectangle {
                        width: 28; height: 28; radius: 14
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: "transparent"; border.color: Color.mPrimary; border.width: 2
                        RotationAnimator on rotation {
                            from: 0; to: 360; duration: 800
                            loops: Animation.Infinite; running: parent.visible
                            easing.type: Easing.Linear
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "fetching stream"
                        color: Color.mOnSurfaceVariant
                        font.pixelSize: 11; font.letterSpacing: 2; opacity: 0.7
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: detailView._withAlpha(detailView._surfaceColor(), 0.52)
                visible: anime?.isLaunchingPlayer ?? false; z: 6

                Column {
                    anchors.centerIn: parent; spacing: 12

                    Rectangle {
                        width: 24; height: 24; radius: 12
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: "transparent"; border.color: Color.mPrimary; border.width: 2
                        RotationAnimator on rotation {
                            from: 0; to: 360; duration: 760
                            loops: Animation.Infinite; running: parent.visible
                            easing.type: Easing.Linear
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "opening player"
                        color: Color.mOnSurfaceVariant
                        font.pixelSize: 11; font.letterSpacing: 2; opacity: 0.8
                    }
                }
            }

            // Error toast
            Rectangle {
                anchors {
                    bottom: parent.bottom
                    horizontalCenter: parent.horizontalCenter
                    bottomMargin: ((anime?.linksError?.length ?? 0) > 0
                        || (anime?.playbackError?.length ?? 0) > 0) ? 56 : 12
                }
                height: 36
                radius: 18
                width: Math.min(parent.width - 32, detailErrText.implicitWidth + 28)
                color: detailView._errorContainerColor()
                visible: (anime?.detailError?.length ?? 0) > 0 && !(anime?.isFetchingDetail ?? false)
                z: 7

                Text {
                    id: detailErrText
                    anchors {
                        fill: parent
                        leftMargin: 14
                        rightMargin: 14
                    }
                    text: anime?.detailError ?? ""
                    font.pixelSize: 11
                    color: detailView._onErrorContainerColor()
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Rectangle {
                anchors {
                    bottom: parent.bottom; horizontalCenter: parent.horizontalCenter
                    bottomMargin: (anime?.playbackError?.length ?? 0) > 0 ? 56 : 12
                }
                height: 36; radius: 18
                width: Math.min(parent.width - 32, linksErrText.implicitWidth + 28)
                color: detailView._errorContainerColor()
                visible: (anime?.linksError?.length ?? 0) > 0 && !(anime?.isFetchingLinks ?? false)
                z: 7

                Text {
                    id: linksErrText
                    anchors {
                        fill: parent
                        leftMargin: 14
                        rightMargin: 14
                    }
                    text: anime?.linksError ?? ""
                    font.pixelSize: 11
                    color: detailView._onErrorContainerColor()
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Rectangle {
                anchors {
                    bottom: parent.bottom; horizontalCenter: parent.horizontalCenter
                    bottomMargin: 12
                }
                height: 36; radius: 18
                width: Math.min(parent.width - 32, playbackErrText.implicitWidth + 28)
                color: detailView._errorContainerColor()
                visible: (anime?.playbackError?.length ?? 0) > 0 && !(anime?.isLaunchingPlayer ?? false)
                z: 7

                Text {
                    id: playbackErrText
                    anchors {
                        fill: parent
                        leftMargin: 14
                        rightMargin: 14
                    }
                    text: anime?.playbackError ?? ""
                    font.pixelSize: 11
                    color: detailView._onErrorContainerColor()
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            ListView {
                id: epList
                anchors.fill: parent; clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: anime?.currentAnime?.episodes ?? []

                onModelChanged: detailView.centerPreferredEpisode(false)
                onVisibleChanged: if (visible) detailView.centerPreferredEpisode(true)
                onContentHeightChanged: detailView.centerPreferredEpisode(false)

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 3; color: Color.mPrimary; opacity: 0.45; radius: 2
                    }
                }

                delegate: Rectangle {
                    width: epList.width; height: 52

                    readonly property var _libEntry: {
                        var _ = anime?.libraryVersion ?? 0  // reactive trigger
                        return anime?.currentAnime
                            ? anime.getLibraryEntry(anime.currentAnime.id) : null
                    }
                    readonly property bool isLastWatched:
                        _libEntry !== null && _libEntry !== undefined
                        && _libEntry.lastWatchedEpNum === String(modelData.number)
                    readonly property bool isWatched:
                        (anime?.libraryVersion ?? 0) >= 0 &&
                        (anime?.isEpisodeWatched(anime?.currentAnime?.id ?? "", modelData.number) ?? false)
                    readonly property bool hasProgress:
                        !isWatched &&
                        (anime?.libraryVersion ?? 0) >= 0 &&
                        (anime?.hasEpisodeProgress(anime?.currentAnime?.id ?? "", modelData.number) ?? false)
                    readonly property real progressRatio:
                        (anime?.libraryVersion ?? 0) >= 0
                        ? (anime?.getEpisodeProgressRatio(anime?.currentAnime?.id ?? "", modelData.number) ?? 0)
                        : 0

                    color: isLastWatched
                        ? detailView._withAlpha(detailView._primaryColor(), 0.07)
                        : (epRowArea.pressed
                            ? Color.mSurfaceVariant
                            : (epRowArea.containsMouse ? Color.mSurface : "transparent"))
                    opacity: isWatched && !isLastWatched ? 0.5 : 1.0
                    Behavior on color { ColorAnimation { duration: 110 } }

                    Rectangle {
                        anchors {
                            bottom: parent.bottom
                            left: parent.left; right: parent.right
                            leftMargin: 64; rightMargin: 56
                        }
                        height: 1; color: detailView._outlineVariantColor(); opacity: 0.22
                    }

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                            leftMargin: 64
                            rightMargin: 56
                            bottomMargin: 3
                        }
                        height: 3
                        radius: 2
                        color: detailView._withAlpha(detailView._outlineVariantColor(), 0.18)
                        visible: hasProgress && progressRatio > 0

                        Rectangle {
                            width: parent.width * progressRatio
                            height: parent.height
                            radius: parent.radius
                            color: Color.mTertiary
                        }
                    }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        spacing: 14

                        Rectangle {
                            width: epPillText.implicitWidth + 16; height: 26; radius: 13
                            color: (isLastWatched || isWatched) ? Color.mPrimary : detailView._primaryContainerColor()

                            Text {
                                id: epPillText; anchors.centerIn: parent
                                text: "Ep." + (modelData.number || "?")
                                font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.5
                                color: (isLastWatched || isWatched) ? Color.mOnPrimary : detailView._onPrimaryContainerColor()
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Episode " + (modelData.number || "")
                            font.pixelSize: 12; color: Color.mOnSurface; elide: Text.ElideRight
                        }

                        // In-progress dot
                        Rectangle {
                            visible: hasProgress
                            width: 6; height: 6; radius: 3
                            color: detailView._tertiaryColor()
                            Layout.alignment: Qt.AlignVCenter
                            opacity: 0.9
                        }

                        Text {
                            text: isWatched ? "✓" : "▶"
                            font.pixelSize: isWatched ? 14 : 13
                            font.bold: isWatched
                            color: isWatched
                                ? detailView._primaryColor()
                                : hasProgress
                                    ? detailView._tertiaryColor()
                                    : (epRowArea.containsMouse ? detailView._primaryColor() : detailView._outlineColor())
                            opacity: isWatched ? 0.8
                                : hasProgress ? 0.9
                                : (epRowArea.containsMouse ? 0.9 : 0.35)
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            Behavior on color   { ColorAnimation  { duration: 120 } }
                        }

                        Item {
                            id: watchToggleButton
                            width: 28
                            height: 28
                            Layout.alignment: Qt.AlignVCenter
                            z: 2

                            Rectangle {
                                anchors.fill: parent
                                radius: 14
                                color: watchToggleArea.containsMouse
                                    ? (isWatched ? detailView._primaryColor() : detailView._primaryContainerColor())
                                    : detailView._withAlpha(detailView._surfaceColor(), 0.7)
                                border.width: 1
                                border.color: isWatched
                                    ? detailView._withAlpha(detailView._primaryColor(), 0.45)
                                    : detailView._withAlpha(detailView._outlineVariantColor(), 0.35)
                                Behavior on color { ColorAnimation { duration: 130 } }
                                Behavior on border.color { ColorAnimation { duration: 130 } }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: isWatched ? "✓" : "+"
                                font.pixelSize: isWatched ? 12 : 14
                                font.bold: true
                                color: isWatched
                                    ? (watchToggleArea.containsMouse ? detailView._onPrimaryColor() : detailView._primaryColor())
                                    : (watchToggleArea.containsMouse ? detailView._onPrimaryContainerColor() : detailView._onSurfaceVariantColor())
                                Behavior on color { ColorAnimation { duration: 130 } }
                            }

                            MouseArea {
                                id: watchToggleArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    mouse.accepted = true
                                    if (!anime?.currentAnime) return
                                    anime.toggleEpisodeWatched(
                                        anime.currentAnime,
                                        modelData.id,
                                        modelData.number
                                    )
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: epRowArea
                        anchors {
                            fill: parent
                            rightMargin: 52
                        }
                        hoverEnabled: true
                        onClicked: {
                            if (!anime?.currentAnime) return
                            anime.fetchStreamLinks(
                                anime.currentAnime.id,
                                modelData.id,
                                modelData.number
                            )
                        }
                    }
                }
            }
        }
    }

    // ── React to selectedLink ─────────────────────────────────────────────────
    Connections {
        target: anime
        enabled: anime !== null

        function onCurrentAnimeChanged() {
            detailView._lastCenteredEpisodeKey = ""
            detailView.centerPreferredEpisode(true)
        }

        function onSelectedLinkChanged() {
            if (!anime?.selectedLink) return
            var lnk = anime.selectedLink
            if (!lnk.url || lnk.url.length === 0) {
                anime.clearStreamLinks()
                return
            }
            anime.commitPendingEpisodeSelection()
            var title = detailView._streamTitle()
            if (title.length > 0)
                title += " — Ep." + anime.currentEpisode
            anime.playWithMpv(
                lnk.url,
                lnk.referer || "",
                title,
                lnk.http_headers || ({}),
                lnk.type || ""
            )
            anime.clearStreamLinks()
        }

    }
}
