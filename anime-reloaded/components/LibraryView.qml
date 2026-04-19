import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.Commons
import qs.Widgets

Item {
    id: libraryView

    property var pluginApi: null
    readonly property var anime: pluginApi?.mainInstance || null
    property string librarySearchQuery: ""
    property var progressFilters: []
    property string typeFilter: "all"
    readonly property var progressFilterOptions: [
        { key: "all", label: "All" },
        { key: "watching", label: "Watching" },
        { key: "completed", label: "Completed" },
        { key: "on_hold", label: "On Hold" },
        { key: "dropped", label: "Dropped" },
        { key: "plan_to_watch", label: "Plan To Watch" }
    ]
    readonly property var typeFilterOptions: [
        { key: "all", label: "All Types" },
        { key: "tv", label: "TV" },
        { key: "short", label: "Short / ONA" },
        { key: "movie", label: "Movie / OVA" },
        { key: "other", label: "Other" }
    ]
    readonly property bool hasActiveFilters:
        (progressFilters?.length ?? 0) > 0 || typeFilter !== "all"

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
        libraryView.animeSelected({
            id:               entry.id,
            name:             entry.name,
            englishName:      entry.englishName,
            nativeName:       entry.nativeName || "",
            thumbnail:        entry.thumbnail,
            score:            entry.score,
            type:             entry.type || "",
            episodeCount:     entry.episodeCount || "",
            availableEpisodes: entry.availableEpisodes || { sub: 0, dub: 0, raw: 0 },
            season:           entry.season || null,
            providerRefs:     entry.providerRefs || ({})
        })
    }

    function filteredLibraryEntries() {
        var entries = anime?.libraryList ?? []
        var query = (librarySearchQuery || "").trim().toLowerCase()
        return entries.filter(function(entry) {
            if (!_matchesProgressFilter(entry) || !_matchesTypeFilter(entry))
                return false
            if (query.length === 0)
                return true
            var haystack = [
                entry.englishName || "",
                entry.name || "",
                entry.nativeName || ""
            ].join(" ").toLowerCase()
            return haystack.indexOf(query) !== -1
        })
    }

    function resetFilters() {
        progressFilters = []
        typeFilter = "all"
    }

    function _isStatusFilterSelected(key) {
        if (key === "all")
            return (progressFilters?.length ?? 0) === 0
        return (progressFilters || []).indexOf(String(key || "")) !== -1
    }

    function toggleStatusFilter(key) {
        var statusKey = String(key || "")
        if (statusKey === "all") {
            progressFilters = []
            return
        }

        var next = (progressFilters || []).slice()
        var index = next.indexOf(statusKey)
        if (index >= 0)
            next.splice(index, 1)
        else
            next.push(statusKey)
        progressFilters = next
    }

    function _activeFilterSummary() {
        var parts = []
        var progressLabels = []
        var typeLabel = null
        for (var i = 0; i < progressFilterOptions.length; i++) {
            var option = progressFilterOptions[i]
            if (option.key === "all")
                continue
            if (_isStatusFilterSelected(option.key))
                progressLabels.push(option.label)
        }
        for (var j = 0; j < typeFilterOptions.length; j++) {
            if (typeFilterOptions[j].key === typeFilter) {
                typeLabel = typeFilterOptions[j]
                break
            }
        }
        if (progressLabels.length > 0)
            parts.push(progressLabels.join(", "))
        if (typeFilter !== "all" && typeLabel)
            parts.push(typeLabel.label)
        return parts.length > 0 ? parts.join(" · ") : "Status and type"
    }

    function _numericValue(value) {
        var parsed = Number(value)
        return isFinite(parsed) ? parsed : 0
    }

    function _entryLastWatched(entry) {
        return _numericValue(entry?.lastWatchedEpNum || 0)
    }

    function _entryWatchedCount(entry) {
        var watched = entry?.watchedEpisodes || []
        var seen = {}
        var total = 0
        for (var i = 0; i < watched.length; i++) {
            var number = String(watched[i] || "")
            if (!number || seen[number])
                continue
            seen[number] = true
            total++
        }
        return total
    }

    function _entryProgressCount(entry) {
        return Math.max(_entryWatchedCount(entry), _entryLastWatched(entry))
    }

    function _entryHasActiveProgress(entry) {
        var progress = entry?.episodeProgress || {}
        var keys = Object.keys(progress)
        for (var i = 0; i < keys.length; i++) {
            if ((anime?.getEpisodeProgress(entry.id, keys[i]) || 0) > 0)
                return true
        }
        return false
    }

    function _entryStarted(entry) {
        return _entryWatchedCount(entry) > 0 ||
            _entryLastWatched(entry) > 0 ||
            _entryHasActiveProgress(entry)
    }

    function _entryProgressState(entry) {
        if (anime?.libraryListStatusState)
            return anime.libraryListStatusState(entry)
        return {
            key: _entryStarted(entry) ? "watching" : "plan_to_watch",
            label: _entryStarted(entry) ? "Watching" : "Plan To Watch"
        }
    }

    function _matchesProgressFilter(entry) {
        var activeFilters = progressFilters || []
        if (activeFilters.length === 0)
            return true
        return activeFilters.indexOf(_entryProgressState(entry).key) !== -1
    }

    function _entryTypeGroup(entry) {
        var type = String(entry?.type || "").toUpperCase()
        if (type === "TV")
            return "tv"
        if (type === "TV_SHORT" || type === "ONA")
            return "short"
        if (type === "MOVIE" || type === "OVA")
            return "movie"
        return "other"
    }

    function _matchesTypeFilter(entry) {
        return typeFilter === "all" || _entryTypeGroup(entry) === typeFilter
    }

    function _malBadgeFill(badge) {
        var tone = String(badge?.tone || "")
        var base = Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.95)
        if (tone === "error")
            return Qt.tint(base, Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.2))
        if (tone === "accent")
            return Qt.tint(base, Qt.rgba(Color.mTertiary.r, Color.mTertiary.g, Color.mTertiary.b, 0.2))
        if (tone === "primary")
            return Qt.tint(base, Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.2))
        return Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.93)
    }

    function _malBadgeBorder(badge) {
        var tone = String(badge?.tone || "")
        if (tone === "error")
            return Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.34)
        if (tone === "accent")
            return Qt.rgba(Color.mTertiary.r, Color.mTertiary.g, Color.mTertiary.b, 0.34)
        if (tone === "primary")
            return Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.34)
        return _withAlpha(_outlineVariantColor(), 0.36)
    }

    function _malBadgeTextColor(badge) {
        var tone = String(badge?.tone || "")
        if (tone === "error")
            return Color.mError
        if (tone === "accent")
            return Color.mTertiary
        if (tone === "primary")
            return Color.mPrimary
        return Color.mOnSurfaceVariant
    }

    function _statusFillColor(key) {
        var status = String(key || "")
        var secondary = _themeColor("mSecondary", Color.mPrimary)
        var tertiary = _themeColor("mTertiary", Color.mPrimary)
        if (status === "watching")
            return Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.92)
        if (status === "completed")
            return Qt.rgba(secondary.r, secondary.g, secondary.b, 0.9)
        if (status === "on_hold")
            return Qt.rgba(tertiary.r, tertiary.g, tertiary.b, 0.9)
        if (status === "dropped")
            return Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.18)
        return Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.88)
    }

    function _statusBorderColor(key) {
        var status = String(key || "")
        var secondary = _themeColor("mSecondary", Color.mPrimary)
        var tertiary = _themeColor("mTertiary", Color.mPrimary)
        if (status === "watching")
            return Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.95)
        if (status === "completed")
            return Qt.rgba(secondary.r, secondary.g, secondary.b, 0.95)
        if (status === "on_hold")
            return Qt.rgba(tertiary.r, tertiary.g, tertiary.b, 0.95)
        if (status === "dropped")
            return Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.42)
        return _withAlpha(_outlineVariantColor(), 0.42)
    }

    function _statusTextColor(key) {
        var status = String(key || "")
        if (status === "watching")
            return Color.mOnPrimary
        if (status === "completed")
            return _themeColor("mOnSecondary", Color.mOnPrimary)
        if (status === "on_hold")
            return _themeColor("mOnTertiary", Color.mOnSurface)
        if (status === "dropped")
            return Color.mError
        return Color.mOnSurface
    }

    function _statusDisplayLabel(state) {
        var key = String(state?.key || "")
        if (key === "plan_to_watch")
            return "Planned"
        return String(state?.label || "")
    }

    function openSearch() {
        librarySearchBar.visible = true
        librarySearchField.forceActiveFocus()
    }

    function toggleSearch() {
        librarySearchBar.visible = !librarySearchBar.visible
        if (librarySearchBar.visible)
            librarySearchField.forceActiveFocus()
        else
            libraryView.closeSearch()
    }

    function closeSearch() {
        librarySearchBar.visible = false
        librarySearchField.text = ""
    }

    TapHandler {
        enabled: librarySearchBar.visible
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: function(eventPoint) {
            var pos = librarySearchBar.mapToItem(libraryView, 0, 0)
            var x = eventPoint.position.x
            var y = eventPoint.position.y
            var insideSearchBar =
                x >= pos.x && x <= pos.x + librarySearchBar.width &&
                y >= pos.y && y <= pos.y + librarySearchBar.height
            if (!insideSearchBar)
                libraryView.closeSearch()
        }
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
                anchors { fill: parent; leftMargin: 18; rightMargin: 10 }
                spacing: 8

                Rectangle {
                    id: libraryWordmark
                    visible: !librarySearchBar.visible
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 19
                    color: libraryTitleArea.containsMouse
                        ? Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.92)
                        : Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.88)
                    border.width: 1
                    border.color: libraryTitleArea.containsMouse
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
                            font.pixelSize: 20
                            font.letterSpacing: 1
                            color: Color.mPrimary
                        }
                        Text {
                            text: "nime Library"
                            font.pixelSize: 20
                            font.letterSpacing: 1
                            color: Color.mOnSurface
                            opacity: libraryTitleArea.containsMouse ? 1 : 0.85
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                        }
                    }

                    MouseArea {
                        id: libraryTitleArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: libraryView.openSearch()
                    }
                }

                Rectangle {
                    id: librarySearchBar
                    Layout.fillWidth: true
                    height: 36
                    radius: 18
                    color: Color.mSurface
                    visible: false
                    border.color: librarySearchField.activeFocus ? Color.mPrimary : _outlineVariantColor()
                    border.width: librarySearchField.activeFocus ? 1.5 : 1

                    TextInput {
                        id: librarySearchField
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            right: libraryClearBtn.left
                            leftMargin: 14
                            rightMargin: 6
                        }
                        color: Color.mOnSurface
                        font.pixelSize: 13
                        clip: true
                        selectByMouse: true
                        onTextChanged: libraryView.librarySearchQuery = text
                        Keys.onEscapePressed: {
                            libraryView.closeSearch()
                        }
                    }

                    Text {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 14 }
                        text: "Search library…"
                        color: Color.mOnSurfaceVariant
                        font.pixelSize: 13
                        visible: librarySearchField.text.length === 0
                        opacity: 0.6
                    }

                    Item {
                        id: libraryClearBtn
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 10 }
                        width: 22
                        height: 22
                        visible: librarySearchField.text.length > 0

                        Rectangle {
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            radius: 9
                            color: libraryClearArea.containsMouse ? _primaryContainerColor() : Color.mSurfaceVariant
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: libraryClearArea.containsMouse ? _onPrimaryContainerColor() : Color.mOnSurfaceVariant
                            font.pixelSize: 9
                            font.bold: true
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        MouseArea {
                            id: libraryClearArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: librarySearchField.text = ""
                        }
                    }
                }

                Rectangle {
                    visible: (anime?.libraryList?.length ?? 0) > 0
                    height: 30
                    width: libCountText.implicitWidth + 20
                    radius: 15
                    color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.92)
                    border.color: _withAlpha(_outlineVariantColor(), 0.42)
                    border.width: 1

                    Text {
                        id: libCountText; anchors.centerIn: parent
                        text: {
                            var total = anime?.libraryList?.length ?? 0
                            var filtered = libraryView.filteredLibraryEntries().length
                            if (libraryView.hasActiveFilters || (libraryView.librarySearchQuery || "").trim().length > 0)
                                return filtered + " of " + total
                            return total + " saved"
                        }
                        font.pixelSize: 10
                        font.letterSpacing: 0.5
                        color: Color.mOnSurfaceVariant
                    }
                }

                HoverIconButton {
                    text: "⌕"
                    iconPixelSize: 18
                    selected: librarySearchBar.visible
                    onClicked: libraryView.toggleSearch()
                }

                HoverIconButton {
                    text: "⚙"
                    iconPixelSize: 15
                    onClicked: libraryView.settingsRequested()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: (anime?.libraryList?.length ?? 0) > 0
            readonly property bool singleRowLayout: width >= 980
            implicitHeight: filterWrap.implicitHeight + 22
            height: visible ? implicitHeight : 0
            color: "transparent"
            clip: true

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1
                color: _outlineVariantColor()
                opacity: 0.32
            }

            Column {
                id: filterWrap
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    leftMargin: 16
                    rightMargin: 16
                    topMargin: 11
                }
                spacing: 10

                Rectangle {
                    width: parent.width
                    radius: 20
                    color: Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.52)
                    border.width: 1
                    border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.16)
                    implicitHeight: filtersColumn.implicitHeight + 24

                    Column {
                        id: filtersColumn
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        RowLayout {
                            width: parent.width
                            spacing: 10

                            Rectangle {
                                implicitWidth: filterLabel.implicitWidth + 20
                                implicitHeight: 24
                                radius: 12
                                color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)
                                border.width: 1
                                border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.24)

                                Text {
                                    id: filterLabel
                                    anchors.centerIn: parent
                                    text: "MAL Status Filters"
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 0.6
                                    color: Color.mPrimary
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: libraryView._activeFilterSummary()
                                font.pixelSize: 11
                                color: Color.mOnSurfaceVariant
                                opacity: 0.84
                                elide: Text.ElideRight
                            }

                            ActionChip {
                                visible: libraryView.hasActiveFilters
                                text: "Reset"
                                controlHeight: 26
                                horizontalPadding: 11
                                fontPixelSize: 9
                                letterSpacing: 0.5
                                boldLabel: false
                                onClicked: libraryView.resetFilters()
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: 10

                            Rectangle {
                                width: parent.parent.parent.singleRowLayout
                                    ? Math.floor((parent.width - parent.spacing) * 0.58)
                                    : parent.width
                                radius: 16
                                color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.82)
                                border.width: 1
                                border.color: _withAlpha(_outlineVariantColor(), 0.34)
                                implicitHeight: progressColumn.implicitHeight + 18

                                Column {
                                    id: progressColumn
                                    anchors.fill: parent
                                    anchors.margins: 9
                                    spacing: 8

                                    Text {
                                        text: "Status"
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.letterSpacing: 0.7
                                        color: Color.mOnSurfaceVariant
                                        opacity: 0.82
                                    }

                                    Flow {
                                        width: parent.width
                                        spacing: 8

                                        Repeater {
                                            model: libraryView.progressFilterOptions

                                            delegate: ChoiceChip {
                                                text: modelData.label
                                                selected: libraryView._isStatusFilterSelected(modelData.key)
                                                fontPixelSize: 11
                                                onClicked: libraryView.toggleStatusFilter(modelData.key)
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.parent.parent.singleRowLayout
                                    ? (parent.width - Math.floor((parent.width - parent.spacing) * 0.58) - parent.spacing)
                                    : parent.width
                                radius: 16
                                color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.82)
                                border.width: 1
                                border.color: _withAlpha(_outlineVariantColor(), 0.34)
                                implicitHeight: typeColumn.implicitHeight + 18

                                Column {
                                    id: typeColumn
                                    anchors.fill: parent
                                    anchors.margins: 9
                                    spacing: 8

                                    Text {
                                        text: "Type"
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.letterSpacing: 0.7
                                        color: Color.mOnSurfaceVariant
                                        opacity: 0.82
                                    }

                                    Flow {
                                        width: parent.width
                                        spacing: 8

                                        Repeater {
                                            model: libraryView.typeFilterOptions

                                            delegate: ChoiceChip {
                                                text: modelData.label
                                                selected: libraryView.typeFilter === modelData.key
                                                fontPixelSize: 11
                                                onClicked: libraryView.typeFilter = modelData.key
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

        // ── Empty state ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: (anime?.libraryList?.length ?? 0) === 0 && (anime?.libraryLoaded ?? false)

            Rectangle {
                width: Math.min(parent.width - 28, 340)
                anchors.centerIn: parent
                radius: 20
                color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.86)
                border.width: 1
                border.color: _withAlpha(_outlineVariantColor(), 0.4)
                implicitHeight: emptyColumn.implicitHeight + 34

                Column {
                    id: emptyColumn
                    anchors.fill: parent
                    anchors.margins: 17
                    spacing: 10

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 42
                        height: 42
                        radius: 21
                        color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)

                        Text {
                            anchors.centerIn: parent
                            text: "⊡"
                            font.pixelSize: 19
                            color: Color.mPrimary
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Your library is empty"
                        font.pixelSize: 15
                        font.bold: true
                        color: Color.mOnSurface
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        lineHeight: 1.35
                        text: "Open an anime from Browse and tap + Library to keep track of what you are watching."
                        font.pixelSize: 11
                        color: Color.mOnSurfaceVariant
                        opacity: 0.74
                        font.letterSpacing: 0.2
                    }
                }
            }
        }

        // ── Loading ───────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: !(anime?.libraryLoaded ?? true)

            Rectangle {
                width: 28; height: 28; radius: 14
                anchors.centerIn: parent
                color: "transparent"; border.color: Color.mPrimary; border.width: 2
                RotationAnimator on rotation {
                    from: 0; to: 360; duration: 800
                    loops: Animation.Infinite; running: parent.visible
                    easing.type: Easing.Linear
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: (anime?.libraryList?.length ?? 0) > 0

            Item {
                anchors.fill: parent

                Item {
                    anchors.fill: parent
                    visible: libraryView.filteredLibraryEntries().length === 0
                    z: 2

                    Column {
                        anchors.centerIn: parent
                        spacing: 10

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "No matches"
                            font.pixelSize: 15
                            font.bold: true
                            color: Color.mOnSurface
                        }

                        Text {
                            width: 280
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: (libraryView.hasActiveFilters || (libraryView.librarySearchQuery || "").trim().length > 0)
                                ? "Try a different title or loosen the active filters."
                                : "Try a different title, English name, or native name."
                            font.pixelSize: 11
                            color: Color.mOnSurfaceVariant
                            opacity: 0.74
                        }
                    }
                }

                GridView {
                    id: libGrid
                    anchors.fill: parent
                    visible: libraryView.filteredLibraryEntries().length > 0
                    topMargin: 10
                    leftMargin: 8
                    rightMargin: 8
                    bottomMargin: 10

                    readonly property var columnsMap: ({ "small": 8, "medium": 5, "large": 3 })
                    readonly property int columns: columnsMap[anime?.posterSize || "medium"]

                    cellWidth: Math.floor((width - leftMargin - rightMargin) / columns)
                    cellHeight: cellWidth * 1.78
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    model: {
                        var _ = anime?.libraryVersion ?? 0  // reactive trigger
                        return libraryView.filteredLibraryEntries()
                    }

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: 3; color: Color.mPrimary; opacity: 0.45; radius: 2
                        }
                    }

                    onContentYChanged: {
                        if (anime) anime.setLibraryScroll(contentY)
                    }

                    onVisibleChanged: {
                        if (!visible || !anime) return
                        Qt.callLater(function() {
                            libGrid.contentY = Math.min(
                                anime.libraryScrollY || 0,
                                Math.max(0, libGrid.contentHeight - libGrid.height)
                            )
                        })
                    }

                    onContentHeightChanged: {
                        if (!visible || !anime) return
                        if ((anime.libraryScrollY || 0) <= 0) return
                        Qt.callLater(function() {
                            libGrid.contentY = Math.min(
                                anime.libraryScrollY || 0,
                                Math.max(0, libGrid.contentHeight - libGrid.height)
                            )
                        })
                    }

                    delegate: Item {
                        width: libGrid.cellWidth
                        height: libGrid.cellHeight

                        readonly property var entry: modelData
                        readonly property int progressCount: libraryView._entryProgressCount(entry)
                        readonly property var progressState: libraryView._entryProgressState(entry)
                        readonly property real activeProgressRatio: {
                            if (!anime || !entry.lastWatchedEpNum) return 0
                            return anime.getEpisodeProgressRatio(entry.id, entry.lastWatchedEpNum)
                        }

                        Rectangle {
                            id: libCard
                            anchors { fill: parent; margins: 5 }
                            radius: 10
                            color: Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.45)
                            clip: true
                            readonly property var malBadge: anime?.malSyncBadge(entry, true)
                                || ({ visible: false, label: "", detail: "", tone: "muted" })

                            // Cover
                            Rectangle {
                                id: libImageWrapper
                                anchors { top: parent.top; left: parent.left; right: parent.right }
                                height: parent.height - libTitleBar.height - libEpBar.height
                                radius: 10
                                color: "transparent"
                                clip: true
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Item {
                                        width: libImageWrapper.width
                                        height: libImageWrapper.height
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: libImageWrapper.radius
                                            color: _themeColor("mOnSurface", Color.mOnSurface)
                                        }

                                        Rectangle {
                                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                            height: libImageWrapper.radius
                                            color: _themeColor("mOnSurface", Color.mOnSurface)
                                        }
                                    }
                                }

                                Image {
                                    id: libCover
                                    anchors.fill: parent
                                    source: entry.thumbnail || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true; cache: true
                                    opacity: status === Image.Ready ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 300 } }

                                    Rectangle {
                                        anchors.fill: parent; color: Color.mSurfaceVariant
                                        visible: libCover.status !== Image.Ready
                                        Text {
                                            anchors.centerIn: parent; text: "◫"
                                            font.pixelSize: 28; color: Color.mOutline; opacity: 0.25
                                        }
                                    }

                                    Column {
                                        anchors {
                                            top: parent.top
                                            left: parent.left
                                            topMargin: 6
                                            leftMargin: 6
                                        }
                                        spacing: 4

                                        Rectangle {
                                            visible: entry.score != null
                                            height: 18
                                            radius: 9
                                            width: libScoreText.implicitWidth + 10
                                            color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.88)
                                            border.width: 1
                                            border.color: _withAlpha(_outlineVariantColor(), 0.38)

                                            Text {
                                                id: libScoreText
                                                anchors.centerIn: parent
                                                text: entry.score ? "★ " + (entry.score).toFixed(1) : ""
                                                font.pixelSize: 8
                                                font.bold: true
                                                color: Color.mPrimary
                                            }
                                        }

                                        Rectangle {
                                            visible: libCard.malBadge?.visible ?? false
                                            height: 18
                                            radius: 9
                                            width: libMalText.implicitWidth + 10
                                            color: libraryView._malBadgeFill(libCard.malBadge)
                                            border.width: 1
                                            border.color: libraryView._malBadgeBorder(libCard.malBadge)

                                            Text {
                                                id: libMalText
                                                anchors.centerIn: parent
                                                text: libCard.malBadge?.label || ""
                                                font.pixelSize: 8
                                                font.bold: true
                                                color: libraryView._malBadgeTextColor(libCard.malBadge)
                                            }

                                            MouseArea {
                                                id: libMalArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.NoButton
                                            }

                                            StyledToolTip {
                                                target: libMalArea
                                                shown: libMalArea.containsMouse
                                                above: false
                                                text: libCard.malBadge?.detail || ""
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: progressState.label.length > 0
                                        anchors { top: parent.top; right: parent.right; topMargin: 6; rightMargin: 6 }
                                        height: 18
                                        width: statusText.implicitWidth + 12
                                        radius: 9
                                        color: libraryView._statusFillColor(progressState.key)
                                        border.width: 1
                                        border.color: libraryView._statusBorderColor(progressState.key)

                                        Text {
                                            id: statusText
                                            anchors.centerIn: parent
                                            text: libraryView._statusDisplayLabel(progressState)
                                            font.pixelSize: 8
                                            font.bold: true
                                            color: libraryView._statusTextColor(progressState.key)
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

                            // Title bar
                            Rectangle {
                                id: libTitleBar
                                anchors { bottom: libEpBar.top; left: parent.left; right: parent.right }
                                height: libTitleText.implicitHeight + 10
                                color: Color.mSurfaceVariant
                                radius: 0

                                Text {
                                    id: libTitleText
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

                            // Last-watched bar
                            Rectangle {
                                id: libEpBar
                                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                height: 28; color: Color.mSurface; radius: 10

                                // Square off top corners
                                Rectangle {
                                    anchors { top: parent.top; left: parent.left; right: parent.right }
                                    height: parent.radius; color: parent.color
                                }

                                Row {
                                    anchors {
                                        verticalCenter: parent.verticalCenter
                                        left: parent.left; leftMargin: 8
                                    }
                                    spacing: 5

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "▶"; font.pixelSize: 7
                                        color: entry.lastWatchedEpNum
                                            ? Color.mPrimary
                                            : libraryView._statusTextColor(progressState.key)
                                        opacity: entry.lastWatchedEpNum ? 1 : 0.56
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: entry.lastWatchedEpNum
                                            ? "Ep. " + entry.lastWatchedEpNum
                                            : libraryView._statusDisplayLabel(progressState)
                                        font.pixelSize: 10; font.letterSpacing: 0.4
                                        color: entry.lastWatchedEpNum
                                            ? Color.mOnSurface
                                            : libraryView._statusTextColor(progressState.key)
                                        opacity: entry.lastWatchedEpNum ? 0.85 : 0.82
                                    }

                                    Rectangle {
                                        visible: progressCount > 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 14; radius: 7
                                        width: watchedCountText.implicitWidth + 8
                                        color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.18)

                                        Text {
                                            id: watchedCountText
                                            anchors.centerIn: parent
                                            text: "✓ " + progressCount
                                            font.pixelSize: 8; font.bold: true
                                            color: Color.mPrimary
                                        }
                                    }
                                }

                                Rectangle {
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        bottom: parent.bottom
                                        leftMargin: 8
                                        rightMargin: 8
                                        bottomMargin: 4
                                    }
                                    height: 3
                                    radius: 2
                                    color: _withAlpha(_outlineVariantColor(), 0.22)
                                    visible: activeProgressRatio > 0

                                    Rectangle {
                                        width: parent.width * activeProgressRatio
                                        height: parent.height
                                        radius: parent.radius
                                        color: Color.mTertiary
                                    }
                                }
                            }

                            Rectangle {
                                id: libraryAction
                                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 8 }
                                width: 32
                                height: 32
                                radius: 16
                                color: libraryActionArea.containsMouse
                                    ? _withAlpha(_errorContainerColor(), 0.96)
                                    : Color.mPrimary
                                border.width: 1
                                border.color: libraryActionArea.containsMouse
                                    ? Color.mError
                                    : Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.6)
                                z: 3

                                Behavior on color { ColorAnimation { duration: 140 } }
                                Behavior on border.color { ColorAnimation { duration: 140 } }

                                NIcon {
                                    anchors.centerIn: parent
                                    icon: "bookmark"
                                    pointSize: 14
                                    color: Color.mOnPrimary
                                    opacity: libraryActionArea.containsMouse ? 0 : 1
                                    scale: libraryActionArea.containsMouse ? 0.7 : 1
                                    Behavior on opacity { NumberAnimation { duration: 110 } }
                                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "−"
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: _onErrorContainerColor()
                                    opacity: libraryActionArea.containsMouse ? 1 : 0
                                    scale: libraryActionArea.containsMouse ? 1 : 0.7
                                    Behavior on opacity { NumberAnimation { duration: 110 } }
                                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                }

                                MouseArea {
                                    id: libraryActionArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton
                                    onClicked: if (anime) anime.removeFromLibrary(entry.id)
                                }

                                StyledToolTip {
                                    target: libraryActionArea
                                    shown: libraryActionArea.containsMouse
                                    above: false
                                    text: "Remove from library"
                                }
                            }

                            // Hover/press overlay
                            Rectangle {
                                anchors.fill: parent; radius: 10; color: Color.mPrimary
                                opacity: libCardArea.pressed ? 0.16 : (libCardArea.containsMouse ? 0.07 : 0)
                                Behavior on opacity { NumberAnimation { duration: 130 } }
                            }

                            transform: Scale {
                                origin.x: libCard.width / 2; origin.y: libCard.height / 2
                                xScale: libCardArea.pressed ? 0.97 : 1.0
                                yScale: libCardArea.pressed ? 0.97 : 1.0
                                Behavior on xScale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                Behavior on yScale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                id: libCardArea; anchors.fill: parent; hoverEnabled: true
                                onClicked: libraryView.openEntry(entry)
                            }
                        }
                    }
                }
            }
        }
    }
}
