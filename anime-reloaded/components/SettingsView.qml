import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQml
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
    id: settingsView

    property var pluginApi: null
    readonly property var anime: pluginApi?.mainInstance || null
    readonly property bool aniListConnected: anime?.aniListSync?.enabled ?? false
    property string aniListAuthInput: anime?.aniListAuthDraft || ""
    property string aniListInspectorFilter: ""
    readonly property var aniListInspectorEntries: {
        var _ = anime?.aniListSyncSummary ?? {}
        var __ = anime?.aniListSyncResults ?? []
        return settingsView._buildAniListInspectorEntries()
    }
    readonly property var aniListInspectorCounts: settingsView._aniListInspectorCounts(aniListInspectorEntries)
    readonly property string effectiveAniListInspectorFilter:
        settingsView._resolvedAniListInspectorFilter()
    readonly property var filteredAniListInspectorEntries:
        settingsView._filterAniListInspectorEntries(aniListInspectorEntries, effectiveAniListInspectorFilter)
    property string malInspectorFilter: ""
    readonly property var malInspectorEntries: {
        var _ = anime?.libraryVersion ?? 0
        var __ = anime?.malSyncResults ?? []
        var ___ = anime?.malSync?.enabled ?? false
        var ____ = anime?.malSync?.lastSyncAt ?? 0
        return settingsView._buildMalInspectorEntries()
    }
    readonly property var malInspectorCounts: settingsView._malInspectorCounts(malInspectorEntries)
    readonly property string effectiveMalInspectorFilter:
        settingsView._resolvedMalInspectorFilter()
    readonly property var filteredMalInspectorEntries:
        settingsView._filterMalInspectorEntries(malInspectorEntries, effectiveMalInspectorFilter)
    readonly property bool wideLayout: width >= 920
    readonly property int localLibraryCount: (anime?.libraryList || []).length

    signal backRequested()

    layer.enabled: visible
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: settingsView.width
            height: settingsView.height
            color: _themeColor("mOnSurface", Color.mOnSurface)
            topLeftRadius: Style.radiusL
            topRightRadius: Style.radiusL
            bottomLeftRadius: 0
            bottomRightRadius: 0
        }
    }

    onAniListConnectedChanged: {
        if (aniListConnected) {
            aniListAuthInput = ""
            if (anime)
                anime.aniListAuthDraft = ""
        }
    }

    onAnimeChanged: {
        aniListAuthInput = anime?.aniListAuthDraft || ""
    }

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

    function _surfaceColor() {
        return _themeColor("mSurface",
            _themeColor("mBackground", Color.mSurface))
    }

    function _surfaceVariantColor() {
        return _themeColor("mSurfaceVariant",
            Qt.tint(_surfaceColor(), _withAlpha(_themeColor("mOnSurface", Color.mOnSurface), 0.06)))
    }

    function _cardFill(tintColor, tintStrength, baseAlpha) {
        var base = Qt.rgba(_surfaceColor().r, _surfaceColor().g, _surfaceColor().b,
            baseAlpha === undefined ? 0.9 : baseAlpha)
        if (!tintColor)
            return base
        return Qt.tint(base, _withAlpha(tintColor, tintStrength === undefined ? 0.08 : tintStrength))
    }

    function _cardBorder(tintColor, tintStrength) {
        var outline = _withAlpha(_outlineVariantColor(), 0.42)
        if (!tintColor)
            return outline
        return Qt.tint(outline, _withAlpha(tintColor, tintStrength === undefined ? 0.12 : tintStrength))
    }

    function _cardHighlight(tintColor, alpha) {
        if (!tintColor)
            return _withAlpha(_themeColor("mOnSurface", Color.mOnSurface), 0.03)
        return _withAlpha(tintColor, alpha === undefined ? 0.08 : alpha)
    }

    function _panelSizeDescription() {
        if (anime?.panelSize === "small")
            return "Compact width for quick checks and tighter desktops."
        if (anime?.panelSize === "large")
            return "Wide drawer with more breathing room for detail-heavy browsing."
        return "Balanced default for everyday browsing and library management."
    }

    function _posterSizeDescription() {
        if (anime?.posterSize === "small")
            return "Denser grids that fit more titles on screen at once."
        if (anime?.posterSize === "large")
            return "Roomier covers with stronger visual focus and easier scanning."
        return "Balanced cover density that matches the rest of the panel."
    }

    function _aniListConnectionSummary() {
        if (anime?.aniListSync?.enabled)
            return anime?.aniListSync?.userName
                ? ("Connected as " + anime.aniListSync.userName)
                : "Connected and ready to sync"
        return "Use your AniList client id, then finish login by pasting the returned result once."
    }

    function _aniListFixedRedirectUri() {
        return String(anime?.aniListSync?.redirectUri || "https://anilist.co/api/v2/oauth/pin")
    }

    function _aniListNeedsFinishStep() {
        if (aniListConnected)
            return false
        if ((settingsView.aniListAuthInput || "").trim().length > 0)
            return true
        return anime?._pendingAniListBrowserAuth ?? false
    }

    function _aniListPrimaryActionLabel() {
        if (aniListConnected)
            return "Reconnect"
        if (_aniListNeedsFinishStep())
            return "Finish Connect"
        return "Open AniList Login"
    }

    function _copyToClipboard(text, message) {
        var value = String(text || "")
        if (value.length === 0)
            return
        Quickshell.clipboardText = value
        ToastService.showNotice(
            "AnimeReloaded",
            String(message || "Copied to clipboard."),
            "device-tv",
            2200
        )
    }

    function _aniListRemoteStatusLabel(value) {
        var status = String(value || "").trim().toUpperCase()
        if (status === "PLANNING")
            return "Plan To Watch"
        if (status === "CURRENT")
            return "Watching"
        if (status === "COMPLETED")
            return "Completed"
        if (status === "PAUSED")
            return "On Hold"
        if (status === "DROPPED")
            return "Dropped"
        if (status === "REPEATING")
            return "Repeating"
        return ""
    }

    function _aniListResultFacts(result) {
        var parts = []
        var watched = Number(result?.watchedEpisodes || 0)
        var remoteStatus = settingsView._aniListRemoteStatusLabel(result?.remoteStatus)
        if (remoteStatus.length > 0)
            parts.push("Status: " + remoteStatus + ".")
        if (watched > 0)
            parts.push("AniList progress: " + watched + " episode" + (watched === 1 ? "" : "s") + ".")
        return parts.join(" ")
    }

    function _aniListResultDetail(baseDetail, result) {
        var facts = settingsView._aniListResultFacts(result)
        if (facts.length === 0)
            return String(baseDetail || "")
        return String(baseDetail || "") + " " + facts
    }

    function _aniListBadgeData(result) {
        var status = String(result?.status || "").toLowerCase()
        if (status === "error") {
            return {
                key: "error",
                tone: "error",
                label: "Failed",
                detail: String(result?.reason || "The latest AniList sync failed for this title.")
            }
        }
        if (status === "skipped") {
            return {
                key: "skipped",
                tone: "muted",
                label: "Skipped",
                detail: String(result?.reason || "The latest AniList sync skipped this title.")
            }
        }
        if (status === "removed") {
            return {
                key: "removed",
                tone: "accent",
                label: "Removed",
                detail: "This title was removed from your AniList list in the latest sync action."
            }
        }
        if (status === "imported") {
            return {
                key: "imported",
                tone: "accent",
                label: "Imported",
                detail: settingsView._aniListResultDetail(
                    "This title was imported from your AniList list.",
                    result
                )
            }
        }
        if (status === "unchanged") {
            return {
                key: "unchanged",
                tone: "muted",
                label: "Unchanged",
                detail: settingsView._aniListResultDetail(
                    "This title was already aligned with AniList.",
                    result
                )
            }
        }
        return {
            key: "synced",
            tone: "primary",
            label: "Synced",
            detail: settingsView._aniListResultDetail(
                status === "updated"
                    ? "The latest AniList sync updated this title successfully."
                    : "The latest AniList sync completed for this title.",
                result
            )
        }
    }

    function _aniListInspectorPriority(item) {
        var key = String(item?.badgeKey || "")
        if (key === "error")
            return 0
        if (key === "skipped")
            return 1
        if (key === "synced")
            return 2
        if (key === "imported")
            return 3
        if (key === "removed")
            return 4
        if (key === "unchanged")
            return 5
        return 6
    }

    function _buildAniListInspectorEntries() {
        var results = anime?.aniListSyncResults || []
        var items = results.map(function(result) {
            var badge = settingsView._aniListBadgeData(result)
            return {
                id: String(result?.id || ""),
                title: String(result?.title || "Untitled"),
                badge: badge,
                badgeKey: String(badge?.key || "unchanged"),
                badgeTone: String(badge?.tone || "muted"),
                remoteStatus: String(result?.remoteStatus || ""),
                watchedEpisodes: Number(result?.watchedEpisodes || 0),
                detail: String(badge?.detail || "")
            }
        })

        items.sort(function(a, b) {
            var priorityDelta = settingsView._aniListInspectorPriority(a) - settingsView._aniListInspectorPriority(b)
            if (priorityDelta !== 0)
                return priorityDelta
            return String(a.title || "").localeCompare(String(b.title || ""))
        })
        return items
    }

    function _aniListInspectorCounts(entries) {
        var list = entries || []
        var counts = {
            total: list.length,
            attention: 0,
            synced: 0,
            unchanged: 0
        }

        for (var i = 0; i < list.length; i++) {
            var key = String((list[i] || {}).badgeKey || "")
            if (key === "error" || key === "skipped")
                counts.attention += 1
            else if (key === "unchanged")
                counts.unchanged += 1
            else
                counts.synced += 1
        }
        return counts
    }

    function _resolvedAniListInspectorFilter() {
        if (aniListInspectorFilter === "attention" || aniListInspectorFilter === "synced" || aniListInspectorFilter === "unchanged")
            return aniListInspectorFilter

        var counts = aniListInspectorCounts || ({})
        if (Number(counts.attention || 0) > 0)
            return "attention"
        if (Number(counts.synced || 0) > 0)
            return "synced"
        return "unchanged"
    }

    function _matchesAniListInspectorFilter(item, filterKey) {
        var key = String(item?.badgeKey || "")
        var filter = String(filterKey || "")
        if (filter === "attention")
            return key === "error" || key === "skipped"
        if (filter === "synced")
            return key !== "error" && key !== "skipped" && key !== "unchanged"
        if (filter === "unchanged")
            return key === "unchanged"
        return true
    }

    function _filterAniListInspectorEntries(entries, filterKey) {
        return (entries || []).filter(function(item) {
            return settingsView._matchesAniListInspectorFilter(item, filterKey)
        })
    }

    function _aniListInspectorSummary() {
        var counts = aniListInspectorCounts || ({})
        var entries = aniListInspectorEntries || []
        if (entries.length === 0)
            return "No AniList sync results are available yet."

        if (Number(counts.attention || 0) > 0)
            return String(counts.attention) + " title"
                + (counts.attention === 1 ? "" : "s")
                + " need attention from the latest AniList sync."
        if (Number(counts.synced || 0) > 0)
            return "Latest AniList sync changed "
                + String(counts.synced) + " title"
                + (counts.synced === 1 ? "" : "s") + " successfully."
        return "Latest AniList sync found "
            + String(counts.unchanged || 0) + " title"
            + (counts.unchanged === 1 ? "" : "s") + " already aligned."
    }

    function _aniListInspectorSectionTitle() {
        if (effectiveAniListInspectorFilter === "attention")
            return "Needs Attention"
        if (effectiveAniListInspectorFilter === "synced")
            return "Recent Changes"
        return "Already Aligned"
    }

    function _aniListInspectorSectionHint() {
        if (effectiveAniListInspectorFilter === "attention")
            return "These titles are the ones that failed or were skipped in the latest AniList sync. The reason is shown under each title."
        if (effectiveAniListInspectorFilter === "synced")
            return "These titles synced successfully in the latest AniList run."
        return "These titles were checked and did not need any change."
    }

    function _aniListInspectorEmptyText() {
        if (effectiveAniListInspectorFilter === "attention")
            return "No AniList issues are currently listed."
        if (effectiveAniListInspectorFilter === "synced")
            return "No successful AniList changes are available to show yet."
        return "No unchanged AniList entries are available to show yet."
    }

    function _aniListInspectorMetaText(item) {
        var parts = []
        if (String(item?.id || "").length > 0)
            parts.push("AniList #" + String(item.id))
        if (String(item?.remoteStatus || "").length > 0)
            parts.push("Remote: " + settingsView._aniListRemoteStatusLabel(item.remoteStatus))
        if (Number(item?.watchedEpisodes || 0) > 0)
            parts.push("AniList watched " + String(item.watchedEpisodes))
        return parts.join(" · ")
    }

    function _malConnectionSummary() {
        if (anime?.malSync?.enabled)
            return anime?.malSync?.userName
                ? ("Connected as " + anime.malSync.userName)
                : "Connected and ready to sync"
        return "Browser-based login, AniList-first metadata, optional push/pull sync."
    }

    function _malToneFill(tone, dense) {
        var alpha = dense === true ? 0.94 : 0.88
        var base = Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, alpha)
        if (tone === "error")
            return Qt.tint(base, Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.18))
        if (tone === "accent")
            return Qt.tint(base, Qt.rgba(Color.mTertiary.r, Color.mTertiary.g, Color.mTertiary.b, 0.18))
        if (tone === "primary")
            return Qt.tint(base, Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.18))
        return base
    }

    function _malToneBorder(tone) {
        if (tone === "error")
            return Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.34)
        if (tone === "accent")
            return Qt.rgba(Color.mTertiary.r, Color.mTertiary.g, Color.mTertiary.b, 0.34)
        if (tone === "primary")
            return Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.34)
        return _withAlpha(_outlineVariantColor(), 0.38)
    }

    function _malToneText(tone) {
        if (tone === "error")
            return Color.mError
        if (tone === "accent")
            return Color.mTertiary
        if (tone === "primary")
            return Color.mPrimary
        return Color.mOnSurfaceVariant
    }

    function _malInspectorPriority(item) {
        var key = String(item?.badgeKey || "")
        if (key === "error")
            return 0
        if (key === "unmapped")
            return 1
        if (key === "skipped")
            return 2
        if (key === "removed")
            return 3
        if (key === "linked")
            return 4
        if (key === "imported")
            return 5
        if (key === "synced")
            return 6
        return 7
    }

    function _buildMalInspectorEntries() {
        var entries = anime?.libraryList || []
        var items = entries.map(function(entry) {
            return anime?.malSyncStatusEntry ? anime.malSyncStatusEntry(entry) : null
        }).filter(function(item) {
            return item !== null
        })

        items.sort(function(a, b) {
            var priorityDelta = settingsView._malInspectorPriority(a) - settingsView._malInspectorPriority(b)
            if (priorityDelta !== 0)
                return priorityDelta
            return String(a.title || "").localeCompare(String(b.title || ""))
        })
        return items
    }

    function _matchesMalInspectorFilter(item, filterKey) {
        var key = String(item?.badgeKey || "")
        var filter = String(filterKey || "")
        if (filter === "attention")
            return settingsView._malNeedsAttention(item)
        if (filter === "synced")
            return key === "synced" || key === "imported"
        if (filter === "ready")
            return key === "linked"
        return true
    }

    function _filterMalInspectorEntries(entries, filterKey) {
        return (entries || []).filter(function(item) {
            return settingsView._matchesMalInspectorFilter(item, filterKey)
        })
    }

    function _malNeedsAttention(item) {
        var key = String(item?.badgeKey || "")
        return key === "error" || key === "unmapped" || key === "skipped" || key === "removed"
    }

    function _malInspectorCounts(entries) {
        var list = entries || []
        var counts = {
            total: list.length,
            mapped: 0,
            attention: 0,
            ready: 0,
            synced: 0
        }

        for (var i = 0; i < list.length; i++) {
            var item = list[i] || ({})
            var key = String(item?.badgeKey || "")
            if (String(item.malId || "").length > 0)
                counts.mapped += 1
            if (_malNeedsAttention(item))
                counts.attention += 1
            else if (key === "linked")
                counts.ready += 1
            else if (key === "synced" || key === "imported")
                counts.synced += 1
        }

        return counts
    }

    function _resolvedMalInspectorFilter() {
        if (malInspectorFilter === "attention" || malInspectorFilter === "ready" || malInspectorFilter === "synced")
            return malInspectorFilter

        var counts = malInspectorCounts || ({})
        if (Number(counts.attention || 0) > 0)
            return "attention"
        if (Number(counts.ready || 0) > 0)
            return "ready"
        if (Number(counts.synced || 0) > 0)
            return "synced"
        return "attention"
    }

    function _malInspectorSummary() {
        var counts = malInspectorCounts || ({})
        var entries = malInspectorEntries || []
        if (entries.length === 0)
            return "No library titles are available for MAL inspection yet."

        if (Number(counts.attention || 0) > 0)
            return String(counts.attention) + " title"
                + (counts.attention === 1 ? "" : "s")
                + " need attention before the next clean sync."
        if (Number(counts.ready || 0) > 0)
            return String(counts.ready) + " mapped title"
                + (counts.ready === 1 ? "" : "s")
                + " are ready to push when you want MAL updated."
        if (Number(counts.synced || 0) > 0)
            return "Recent MAL sync state looks healthy across "
                + String(counts.synced) + " title"
                + (counts.synced === 1 ? "" : "s") + "."
        return String(counts.total || 0) + " titles are tracked locally, but none are mapped to MAL yet."
    }

    function _malInspectorSectionTitle() {
        if (effectiveMalInspectorFilter === "attention")
            return "Needs Attention"
        if (effectiveMalInspectorFilter === "ready")
            return "Ready To Push"
        return "Recently Synced"
    }

    function _malInspectorSectionHint() {
        if (effectiveMalInspectorFilter === "attention")
            return "Review these titles first. They are the ones most likely to block or confuse your next MAL sync."
        if (effectiveMalInspectorFilter === "ready")
            return "These titles are mapped cleanly. Push when you want local watch progress reflected on MAL."
        return "These titles are already aligned. No action is needed unless you changed progress locally."
    }

    function _malInspectorEmptyText() {
        if (effectiveMalInspectorFilter === "attention")
            return "Nothing currently needs MAL attention."
        if (effectiveMalInspectorFilter === "ready")
            return "No mapped titles are currently waiting for a manual push."
        return "No recently synced titles are available to show yet."
    }

    function _malInspectorMetaText(item) {
        var parts = []
        if (String(item?.malId || "").length > 0)
            parts.push("MAL #" + String(item.malId))
        if (String(item?.remoteStatus || "").length > 0)
            parts.push("Remote: " + String(item.remoteStatus))
        else if (String(item?.badgeKey || "") === "linked")
            parts.push("Mapped and ready")
        parts.push(String(item?.localProgress || ""))
        if (Number(item?.remoteWatchedEpisodes || 0) > 0)
            parts.push("MAL watched " + String(item.remoteWatchedEpisodes))
        return parts.filter(function(part) {
            return String(part || "").length > 0
        }).join(" · ")
    }

    function _malInspectorDetailText(item) {
        if (!settingsView._malNeedsAttention(item))
            return ""
        return String(item?.detail || "")
    }

    component SettingsCard: Rectangle {
        id: settingsCard

        property color tintColor: Color.mPrimary
        property real tintStrength: 0.08
        property real baseAlpha: 0.9
        property real contentPadding: 16
        property real contentSpacing: 12
        default property alias contentData: contentColumn.data

        radius: 22
        color: settingsView._cardFill(tintColor, tintStrength, baseAlpha)
        border.width: 1
        border.color: settingsView._cardBorder(tintColor, tintStrength + 0.06)
        implicitHeight: contentColumn.implicitHeight + contentPadding * 2

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 1
                rightMargin: 1
                topMargin: 1
            }
            height: 1
            radius: 1
            color: settingsView._cardHighlight(settingsCard.tintColor, 0.1)
            opacity: 0.75
        }

        Column {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: settingsCard.contentPadding
            spacing: settingsCard.contentSpacing
        }
    }

    component SummaryPill: Rectangle {
        id: summaryPill

        property string label: ""
        property color toneColor: Color.mPrimary
        property color textColor: Color.mOnSurface
        property real maxWidth: 32000

        implicitWidth: Math.min(maxWidth, labelText.implicitWidth + 20)
        implicitHeight: 30
        radius: 15
        clip: true
        color: Qt.tint(
            Qt.rgba(settingsView._surfaceColor().r, settingsView._surfaceColor().g, settingsView._surfaceColor().b, 0.9),
            settingsView._withAlpha(toneColor, 0.14)
        )
        border.width: 1
        border.color: settingsView._withAlpha(toneColor, 0.24)

        Text {
            id: labelText
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 10
                rightMargin: 10
            }
            text: summaryPill.label
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.pixelSize: 11
            font.bold: true
            color: summaryPill.textColor
        }
    }

    component SettingsInsetPanel: Rectangle {
        id: insetPanel

        property color tintColor: Color.mPrimary
        property real tintStrength: 0.05
        property real baseAlpha: 0.86
        property real contentPadding: 12
        property real contentSpacing: 8
        default property alias contentData: insetContent.data

        radius: 18
        color: settingsView._cardFill(tintColor, tintStrength, baseAlpha)
        border.width: 1
        border.color: settingsView._cardBorder(tintColor, tintStrength + 0.05)
        implicitHeight: insetContent.implicitHeight + contentPadding * 2

        Column {
            id: insetContent
            anchors.fill: parent
            anchors.margins: insetPanel.contentPadding
            spacing: insetPanel.contentSpacing
        }
    }

    component SettingChoiceButton: ChoiceChip {
        property bool active: false

        selected: active
        minWidth: 92
        controlHeight: 38
        horizontalPadding: 18
        fontPixelSize: 12
        letterSpacing: 0.3
        idleBackgroundColor: Color.mSurface
        hoverBackgroundColor: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.18)
        idleBorderColor: settingsView._withAlpha(settingsView._outlineVariantColor(), 0.55)
        hoverTextColor: Color.mPrimary
        idleTextColor: Color.mOnSurface
    }

    component SettingTextField: Rectangle {
        id: fieldRoot

        property string value: ""
        property string placeholderText: ""
        property bool secret: false
        signal textEdited(string text)

        implicitHeight: 40
        radius: 20
        color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.92)
        border.width: input.activeFocus ? 1.5 : 1
        border.color: input.activeFocus
            ? Color.mPrimary
            : settingsView._withAlpha(settingsView._outlineVariantColor(), 0.5)

        Behavior on border.color { ColorAnimation { duration: 160 } }

        Binding {
            target: input
            property: "text"
            value: fieldRoot.value
            when: !input.activeFocus
        }

        TextInput {
            id: input
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 14
                rightMargin: 14
            }
            color: Color.mOnSurface
            font.pixelSize: 12
            clip: true
            selectByMouse: true
            echoMode: fieldRoot.secret ? TextInput.Password : TextInput.Normal
            onTextEdited: function() {
                fieldRoot.textEdited(text)
            }
        }

        Text {
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
                leftMargin: 14
            }
            text: fieldRoot.placeholderText
            color: Color.mOnSurfaceVariant
            font.pixelSize: 12
            opacity: 0.58
            visible: input.text.length === 0
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.08) }
            GradientStop { position: 1.0; color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.12) }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

            // ── Header ────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 68
            color: "transparent"
            z: 2

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1
                color: _outlineVariantColor()
                opacity: 0.35
            }

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: 10
                    rightMargin: 16
                    topMargin: 8
                    bottomMargin: 8
                }
                spacing: 10

                HoverIconButton {
                    text: "←"
                    buttonSize: 40
                    innerSize: 40
                    iconPixelSize: 18
                    idleOpacity: 0.82
                    activeOpacity: 1.0
                    onClicked: settingsView.backRequested()
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 46
                    radius: 23
                    color: settingsView._cardFill(Color.mPrimary, 0.08, 0.9)
                    border.width: 1
                    border.color: settingsView._cardBorder(Color.mPrimary, 0.14)

                    RowLayout {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 14
                            rightMargin: 12
                        }
                        spacing: 8

                        Rectangle {
                            width: 28
                            height: 28
                            radius: 14
                            color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.16)

                            Text {
                                anchors.centerIn: parent
                                text: "⚙"
                                font.pixelSize: 13
                                color: Color.mPrimary
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            Text {
                                text: "Settings"
                                font.pixelSize: 14
                                font.bold: true
                                color: Color.mOnSurface
                            }

                            Text {
                                text: "Layout, density, and sync preferences"
                                font.pixelSize: 10
                                color: Color.mOnSurfaceVariant
                                opacity: 0.72
                            }
                        }

                        SummaryPill {
                            label: settingsView.localLibraryCount + " saved"
                            toneColor: Color.mPrimary
                            textColor: Color.mPrimary
                        }
                    }
                }
            }
        }

        // ── Content ───────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"

            ScrollView {
                id: settingsScroll
                anchors.fill: parent
                anchors.margins: 14
                contentWidth: availableWidth
                clip: true

                Column {
                    width: settingsScroll.availableWidth
                    spacing: 16

                    SettingsCard {
                        width: parent.width
                        tintColor: Color.mPrimary
                        tintStrength: 0.12
                        baseAlpha: 0.94
                        contentPadding: 18
                        contentSpacing: 14

                        RowLayout {
                            width: parent.width
                            spacing: 16

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: "Tune AnimeReloaded"
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: Color.mOnSurface
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "Refine panel density, keep browsing comfortable, and manage AniList or MyAnimeList sync without leaving the plugin."
                                    wrapMode: Text.Wrap
                                    lineHeight: 1.35
                                    font.pixelSize: 11
                                    color: Color.mOnSurfaceVariant
                                    opacity: 0.82
                                }
                            }

                            Rectangle {
                                visible: settingsView.wideLayout
                                Layout.preferredWidth: 86
                                Layout.preferredHeight: 72
                                radius: 18
                                color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)
                                border.width: 1
                                border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.22)

                                Text {
                                    anchors.centerIn: parent
                                    text: "AR"
                                    font.pixelSize: 24
                                    font.bold: true
                                    color: Color.mPrimary
                                    opacity: 0.9
                                }
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: 8

                            SummaryPill {
                                label: "Panel " + String(anime?.panelSize || "medium")
                                toneColor: Color.mPrimary
                                textColor: Color.mPrimary
                            }

                            SummaryPill {
                                label: "Posters " + String(anime?.posterSize || "medium")
                                toneColor: Color.mPrimary
                                textColor: Color.mPrimary
                            }

                            SummaryPill {
                                label: anime?.aniListSync?.enabled ? "AniList connected" : "AniList optional"
                                toneColor: anime?.aniListSync?.enabled ? Color.mPrimary : Color.mOnSurfaceVariant
                                textColor: anime?.aniListSync?.enabled ? Color.mPrimary : Color.mOnSurfaceVariant
                            }

                            SummaryPill {
                                label: anime?.malSync?.enabled ? "MAL connected" : "MAL optional"
                                toneColor: anime?.malSync?.enabled ? Color.mTertiary : Color.mOnSurfaceVariant
                                textColor: anime?.malSync?.enabled ? Color.mTertiary : Color.mOnSurfaceVariant
                            }

                            SummaryPill {
                                label: settingsView.localLibraryCount + " in library"
                                toneColor: Color.mPrimary
                                textColor: Color.mOnSurface
                            }
                        }
                    }

                    GridLayout {
                        width: parent.width
                        columns: settingsView.wideLayout ? 2 : 1
                        columnSpacing: 16
                        rowSpacing: 16

                        SettingsCard {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            tintColor: Color.mPrimary
                            tintStrength: anime?.panelSize === "large" ? 0.1 : 0.07

                            Row {
                                spacing: 10

                                Rectangle {
                                    width: 30
                                    height: 30
                                    radius: 15
                                    color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "▣"
                                        font.pixelSize: 12
                                        color: Color.mPrimary
                                    }
                                }

                                Column {
                                    spacing: 2

                                    Text {
                                        text: "Panel Size"
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: Color.mOnSurface
                                    }

                                    Text {
                                        text: "Control how wide the drawer feels when browsing."
                                        font.pixelSize: 11
                                        color: Color.mOnSurfaceVariant
                                        opacity: 0.72
                                    }
                                }
                            }

                            Flow {
                                width: parent.width
                                spacing: 10

                                Repeater {
                                    model: [
                                        { label: "Small",  value: "small" },
                                        { label: "Medium", value: "medium" },
                                        { label: "Large",  value: "large" }
                                    ]

                                    delegate: SettingChoiceButton {
                                        text: modelData.label
                                        active: anime?.panelSize === modelData.value
                                        onClicked: if (anime) anime.setSetting("panelSize", modelData.value)
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                text: settingsView._panelSizeDescription()
                                wrapMode: Text.Wrap
                                lineHeight: 1.35
                                font.pixelSize: 10
                                color: Color.mOnSurfaceVariant
                                opacity: 0.72
                            }
                        }

                        SettingsCard {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            tintColor: Color.mPrimary
                            tintStrength: anime?.posterSize === "large" ? 0.1 : 0.07

                            Row {
                                spacing: 10

                                Rectangle {
                                    width: 30
                                    height: 30
                                    radius: 15
                                    color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "◫"
                                        font.pixelSize: 12
                                        color: Color.mPrimary
                                    }
                                }

                                Column {
                                    spacing: 2

                                    Text {
                                        text: "Poster Size"
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: Color.mOnSurface
                                    }

                                    Text {
                                        text: "Adjust cover density without changing the rest of the layout."
                                        font.pixelSize: 11
                                        color: Color.mOnSurfaceVariant
                                        opacity: 0.72
                                    }
                                }
                            }

                            Flow {
                                width: parent.width
                                spacing: 10

                                Repeater {
                                    model: [
                                        { label: "Small",  value: "small" },
                                        { label: "Medium", value: "medium" },
                                        { label: "Large",  value: "large" }
                                    ]

                                    delegate: SettingChoiceButton {
                                        text: modelData.label
                                        active: anime?.posterSize === modelData.value
                                        enabled: !(anime?.panelSize === "small" && modelData.value === "small")
                                        onClicked: if (anime) anime.setSetting("posterSize", modelData.value)
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                text: settingsView._posterSizeDescription()
                                wrapMode: Text.Wrap
                                lineHeight: 1.35
                                font.pixelSize: 10
                                color: Color.mOnSurfaceVariant
                                opacity: 0.72
                            }
                        }
                    }

                    SettingsCard {
                        width: parent.width
                        tintColor: Color.mPrimary
                        tintStrength: 0.06

                        Row {
                            spacing: 10

                            Rectangle {
                                width: 30
                                height: 30
                                radius: 15
                                color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)

                                Text {
                                    anchors.centerIn: parent
                                    text: "↓"
                                    font.pixelSize: 13
                                    color: Color.mPrimary
                                }
                            }

                            Column {
                                spacing: 2

                                Text {
                                    text: "Episode Downloads"
                                    font.pixelSize: 14
                                    font.bold: true
                                    color: Color.mOnSurface
                                }

                                Text {
                                    text: "Pick a folder for saved episodes. Leave it empty to keep using the default AnimeReloaded downloads folder."
                                    font.pixelSize: 11
                                    color: Color.mOnSurfaceVariant
                                    opacity: 0.72
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 6

                            Text {
                                text: "Download Folder"
                                font.pixelSize: 10
                                font.bold: true
                                color: Color.mOnSurface
                            }

                            SettingTextField {
                                width: parent.width
                                value: anime?.episodeDownloadPath || ""
                                placeholderText: anime?.defaultEpisodeDownloadPath || ""
                                onTextEdited: function(text) {
                                    if (anime)
                                        anime.setSetting("episodeDownloadPath", text)
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: "Current location: " + String(anime?.effectiveEpisodeDownloadPath || "")
                            wrapMode: Text.Wrap
                            lineHeight: 1.35
                            font.pixelSize: 10
                            color: Color.mOnSurfaceVariant
                            opacity: 0.74
                        }

                        Flow {
                            width: parent.width
                            spacing: 8

                            ActionChip {
                                text: "Choose Folder"
                                leadingText: "↓"
                                onClicked: downloadFolderPicker.openFilePicker()
                            }

                            ActionChip {
                                text: "Use Default"
                                leadingText: "↺"
                                visible: String(anime?.episodeDownloadPath || "").trim().length > 0
                                onClicked: if (anime) anime.setSetting("episodeDownloadPath", "")
                            }
                        }

                        Text {
                            visible: anime?.isDownloadingEpisode ?? false
                            width: parent.width
                            text: "A download is currently in progress."
                            wrapMode: Text.Wrap
                            lineHeight: 1.35
                            font.pixelSize: 10
                            color: Color.mPrimary
                            opacity: 0.9
                        }

                        NFilePicker {
                            id: downloadFolderPicker
                            title: "Select episode download folder"
                            initialPath: anime?.effectiveEpisodeDownloadPath || anime?.defaultEpisodeDownloadPath || ""
                            selectionMode: "folders"

                            onAccepted: function(paths) {
                                if (paths.length > 0 && anime)
                                    anime.setSetting("episodeDownloadPath", paths[0])
                            }
                        }
                    }

                    SettingsCard {
                        visible: false  // Hidden for now; keep mirror preference wiring intact.
                        width: parent.width
                        tintColor: Color.mPrimary

                        Column {
                            id: providerSection
                            width: parent.width
                            spacing: 12

                            RowLayout {
                                width: parent.width
                                spacing: 10

                                Rectangle {
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "↺"
                                        font.pixelSize: 12
                                        color: Color.mPrimary
                                    }
                                }

                                Column {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: "Preferred Stream Mirror"
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: Color.mOnSurface
                                    }

                                    Text {
                                        text: "Prioritize an AllAnime-backed mirror while keeping fallback behavior"
                                        font.pixelSize: 11
                                        color: Color.mOnSurfaceVariant
                                        opacity: 0.72
                                    }
                                }
                            }

                            Flow {
                                width: parent.width
                                spacing: 10

                                Repeater {
                                    model: [
                                        { label: "Auto", value: "auto" },
                                        { label: "Default", value: "default" },
                                        { label: "SharePoint", value: "sharepoint" },
                                        { label: "HiAnime", value: "hianime" },
                                        { label: "YouTube", value: "youtube" }
                                    ]

                                    delegate: SettingChoiceButton {
                                        text: modelData.label
                                        active: anime?.preferredProvider === modelData.value
                                        onClicked: if (anime) anime.setSetting("preferredProvider", modelData.value)
                                    }
                                }
                            }
                        }
                    }

                    SettingsCard {
                        width: parent.width
                        tintColor: anime?.aniListSync?.enabled ? Color.mPrimary : Color.mSecondary
                        tintStrength: anime?.aniListSync?.enabled ? 0.1 : 0.07

                        Column {
                            width: parent.width
                            spacing: 14

                            RowLayout {
                                width: parent.width
                                spacing: 10

                                Rectangle {
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "A"
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: Color.mPrimary
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: "AniList Sync"
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: Color.mOnSurface
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "AnimeReloaded already uses AniList metadata. This section adds direct account sync so your local library can pull, push, and import progress against your AniList account."
                                        wrapMode: Text.Wrap
                                        lineHeight: 1.35
                                        font.pixelSize: 11
                                        color: Color.mOnSurfaceVariant
                                        opacity: 0.76
                                    }
                                }
                            }

                            Flow {
                                width: parent.width
                                spacing: 8

                                SummaryPill {
                                    label: settingsView._aniListConnectionSummary()
                                    maxWidth: settingsView.wideLayout ? 340 : Math.max(180, parent.width - 12)
                                    toneColor: anime?.aniListSync?.enabled ? Color.mPrimary : Color.mSecondary
                                    textColor: anime?.aniListSync?.enabled ? Color.mPrimary : Color.mOnSurface
                                }

                                SummaryPill {
                                    label: anime?.aniListSync?.autoPush ? "Auto Push enabled" : "Manual push"
                                    toneColor: anime?.aniListSync?.autoPush ? Color.mPrimary : Color.mOnSurfaceVariant
                                    textColor: anime?.aniListSync?.autoPush ? Color.mPrimary : Color.mOnSurfaceVariant
                                }
                            }

                            Rectangle {
                                width: parent.width
                                radius: 18
                                color: settingsView._cardFill(
                                    anime?.aniListSync?.enabled ? Color.mPrimary : Color.mSecondary,
                                    anime?.aniListSync?.enabled ? 0.08 : 0.06,
                                    0.92
                                )
                                border.width: 1
                                border.color: settingsView._cardBorder(
                                    anime?.aniListSync?.enabled ? Color.mPrimary : Color.mSecondary,
                                    0.16
                                )
                                implicitHeight: aniListStatusColumn.implicitHeight + 22

                                Column {
                                    id: aniListStatusColumn
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    SettingsInsetPanel {
                                        width: parent.width
                                        tintColor: anime?.aniListSync?.enabled ? Color.mPrimary : Color.mSecondary
                                        tintStrength: anime?.aniListSync?.enabled ? 0.08 : 0.05
                                        baseAlpha: 0.92
                                        contentSpacing: 10

                                        Text {
                                            text: "Connection"
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: Color.mOnSurface
                                        }

                                        Column {
                                            width: parent.width
                                            spacing: 6

                                            Text {
                                                text: "AniList Client ID"
                                                font.pixelSize: 10
                                                font.bold: true
                                                color: Color.mOnSurface
                                            }

                                            SettingTextField {
                                                width: parent.width
                                                value: anime?.aniListSync?.clientId || ""
                                                placeholderText: "Required for browser login"
                                                onTextEdited: function(text) {
                                                    if (anime) anime.setAniListSyncField("clientId", text)
                                                }
                                            }
                                        }

                                        Flow {
                                            width: parent.width
                                            spacing: 8

                                            SummaryPill {
                                                label: "Redirect URI"
                                                toneColor: Color.mOnSurfaceVariant
                                                textColor: Color.mOnSurfaceVariant
                                            }

                                            Rectangle {
                                                id: aniListRedirectPill
                                                width: Math.min(
                                                    settingsView.wideLayout ? 360 : Math.max(200, parent.width - 12),
                                                    aniListRedirectText.implicitWidth + 26
                                                )
                                                implicitHeight: 30
                                                radius: 15
                                                clip: true
                                                color: aniListRedirectArea.containsMouse
                                                    ? Qt.tint(
                                                        Qt.rgba(settingsView._surfaceColor().r, settingsView._surfaceColor().g, settingsView._surfaceColor().b, 0.92),
                                                        settingsView._withAlpha(Color.mPrimary, 0.18)
                                                    )
                                                    : Qt.tint(
                                                        Qt.rgba(settingsView._surfaceColor().r, settingsView._surfaceColor().g, settingsView._surfaceColor().b, 0.9),
                                                        settingsView._withAlpha(Color.mPrimary, 0.14)
                                                    )
                                                border.width: 1
                                                border.color: settingsView._withAlpha(Color.mPrimary, aniListRedirectArea.containsMouse ? 0.34 : 0.24)

                                                Behavior on color { ColorAnimation { duration: 140 } }
                                                Behavior on border.color { ColorAnimation { duration: 140 } }

                                                Text {
                                                    id: aniListRedirectText
                                                    anchors {
                                                        left: parent.left
                                                        right: copyHint.left
                                                        verticalCenter: parent.verticalCenter
                                                        leftMargin: 10
                                                        rightMargin: 8
                                                    }
                                                    text: settingsView._aniListFixedRedirectUri()
                                                    elide: Text.ElideRight
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                    color: Color.mPrimary
                                                }

                                                Text {
                                                    id: copyHint
                                                    anchors {
                                                        right: parent.right
                                                        verticalCenter: parent.verticalCenter
                                                        rightMargin: 9
                                                    }
                                                    text: "Copy"
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                    color: Color.mPrimary
                                                    opacity: 0.82
                                                }

                                                MouseArea {
                                                    id: aniListRedirectArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: settingsView._copyToClipboard(
                                                        settingsView._aniListFixedRedirectUri(),
                                                        "AniList redirect URI copied."
                                                    )
                                                }
                                            }
                                        }

                                        Column {
                                            width: parent.width
                                            spacing: 6
                                            visible: settingsView._aniListNeedsFinishStep()

                                            Text {
                                                text: "Callback URL or Access Token"
                                                font.pixelSize: 10
                                                font.bold: true
                                                color: Color.mOnSurface
                                            }

                                            SettingTextField {
                                                width: parent.width
                                                value: settingsView.aniListAuthInput
                                                placeholderText: "Paste the returned AniList callback URL or raw token"
                                                onTextEdited: function(text) {
                                                    settingsView.aniListAuthInput = text
                                                    if (anime)
                                                        anime.aniListAuthDraft = text
                                                }
                                            }
                                        }

                                        Text {
                                            width: parent.width
                                            text: anime?.aniListSync?.enabled
                                                ? ("Connected" + (anime?.aniListSync?.userName ? " as " + anime.aniListSync.userName : "") + ". You can reconnect any time with a fresh token.")
                                                : (settingsView._aniListNeedsFinishStep()
                                                    ? "AniList login is open. When AniList shows the callback URL or access token, paste it above and finish the connection."
                                                    : "Create an AniList app, set the redirect URI shown above, enter its client id here, then start the browser login.")
                                            wrapMode: Text.Wrap
                                            lineHeight: 1.35
                                            font.pixelSize: 10
                                            color: Color.mOnSurfaceVariant
                                            opacity: 0.72
                                        }

                                        Flow {
                                            width: parent.width
                                            spacing: 8

                                            ActionChip {
                                                text: settingsView._aniListPrimaryActionLabel()
                                                leadingText: "A"
                                                enabled: !(anime?.isAniListSyncBusy ?? false)
                                                onClicked: {
                                                    if (!anime) return
                                                    if (settingsView._aniListNeedsFinishStep())
                                                        anime.completeAniListBrowserAuth(settingsView.aniListAuthInput, true)
                                                    else {
                                                        settingsView.aniListAuthInput = ""
                                                        anime.aniListAuthDraft = ""
                                                        anime.startAniListBrowserAuth()
                                                    }
                                                }
                                            }

                                            ActionChip {
                                                visible: !aniListConnected && settingsView._aniListNeedsFinishStep()
                                                text: "Open Again"
                                                leadingText: "↗"
                                                enabled: !(anime?.isAniListSyncBusy ?? false)
                                                onClicked: {
                                                    settingsView.aniListAuthInput = ""
                                                    if (anime)
                                                        anime.aniListAuthDraft = ""
                                                    if (anime) anime.startAniListBrowserAuth()
                                                }
                                            }

                                            ActionChip {
                                                text: "Refresh"
                                                leadingText: "↻"
                                                enabled: (anime?.aniListSync?.enabled ?? false)
                                                    && !(anime?.isAniListSyncBusy ?? false)
                                                onClicked: if (anime) anime.refreshAniListSyncSession(true)
                                            }

                                            ActionChip {
                                                text: "Disconnect"
                                                leadingText: "✕"
                                                visible: anime?.aniListSync?.enabled ?? false
                                                enabled: (anime?.aniListSync?.enabled ?? false)
                                                    && !(anime?.isAniListSyncBusy ?? false)
                                                baseColor: Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.86)
                                                hoverColor: Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.18)
                                                hoverBorderColor: Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.4)
                                                hoverTextColor: Color.mError
                                                onClicked: if (anime) anime.clearAniListSyncSession()
                                            }
                                        }

                                        Text {
                                            visible: (anime?.aniListSyncMessage || "").length > 0
                                            width: parent.width
                                            text: anime?.aniListSyncMessage || ""
                                            wrapMode: Text.Wrap
                                            font.pixelSize: 11
                                            color: Color.mPrimary
                                        }

                                        Text {
                                            visible: (anime?.aniListSyncError || "").length > 0
                                            width: parent.width
                                            text: anime?.aniListSyncError || ""
                                            wrapMode: Text.Wrap
                                            font.pixelSize: 11
                                            color: Color.mError
                                        }
                                    }

                                    GridLayout {
                                        width: parent.width
                                        columns: settingsView.wideLayout ? 2 : 1
                                        columnSpacing: 12
                                        rowSpacing: 12

                                        SettingsInsetPanel {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignTop
                                            tintColor: Color.mPrimary
                                            tintStrength: 0.05
                                            baseAlpha: 0.9
                                            contentSpacing: 8

                                            Text {
                                                text: "Sync Mode"
                                                font.pixelSize: 11
                                                font.bold: true
                                                color: Color.mOnSurface
                                            }

                                            Text {
                                                width: parent.width
                                                text: "Choose whether local progress should wait for a manual push or update AniList automatically after watch changes."
                                                wrapMode: Text.Wrap
                                                lineHeight: 1.35
                                                font.pixelSize: 10
                                                color: Color.mOnSurfaceVariant
                                                opacity: 0.72
                                            }

                                            Flow {
                                                width: parent.width
                                                spacing: 10

                                                Repeater {
                                                    model: [
                                                        { label: "Manual", value: false },
                                                        { label: "Auto Push", value: true }
                                                    ]

                                                    delegate: SettingChoiceButton {
                                                        text: modelData.label
                                                        active: (anime?.aniListSync?.autoPush === true) === modelData.value
                                                        onClicked: if (anime) anime.setAniListSyncField("autoPush", modelData.value)
                                                    }
                                                }
                                            }

                                            Text {
                                                width: parent.width
                                                text: anime?.aniListSync?.autoPush
                                                    ? "Auto Push sends local watch changes to AniList after a short delay. Pulls and imports never push back automatically."
                                                    : "Manual only updates AniList when you press Push To AniList."
                                                wrapMode: Text.Wrap
                                                lineHeight: 1.35
                                                font.pixelSize: 10
                                                color: Color.mOnSurfaceVariant
                                                opacity: 0.7
                                            }
                                        }

                                        SettingsInsetPanel {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignTop
                                            tintColor: anime?.aniListSync?.enabled ? Color.mPrimary : Color.mSecondary
                                            tintStrength: anime?.aniListSync?.enabled ? 0.06 : 0.05
                                            baseAlpha: 0.9
                                            contentSpacing: 8

                                            Text {
                                                text: "Sync Actions"
                                                font.pixelSize: 11
                                                font.bold: true
                                                color: Color.mOnSurface
                                            }

                                            Text {
                                                width: parent.width
                                                text: "Pull imports remote progress and new AniList entries. Push sends your local progress back to AniList."
                                                wrapMode: Text.Wrap
                                                lineHeight: 1.35
                                                font.pixelSize: 10
                                                color: Color.mOnSurfaceVariant
                                                opacity: 0.72
                                            }

                                            Flow {
                                                width: parent.width
                                                spacing: 10

                                                ActionChip {
                                                    text: "Pull From AniList"
                                                    leadingText: "↓"
                                                    enabled: !(anime?.isAniListSyncBusy ?? false)
                                                    onClicked: if (anime) anime.pullAniListSync(true)
                                                }

                                                ActionChip {
                                                    text: "Push To AniList"
                                                    leadingText: "↑"
                                                    enabled: !(anime?.isAniListSyncBusy ?? false)
                                                    onClicked: if (anime) anime.pushAniListSync(true)
                                                }
                                            }

                                            Text {
                                                width: parent.width
                                                text: anime?.aniListSync?.lastSyncAt
                                                    ? ("Last " + (anime?.aniListSync?.lastSyncDirection || "sync") + " · " + new Date(Number(anime.aniListSync.lastSyncAt) * 1000).toLocaleString())
                                                    : "No successful AniList sync yet."
                                                wrapMode: Text.Wrap
                                                lineHeight: 1.35
                                                font.pixelSize: 10
                                                color: Color.mOnSurfaceVariant
                                                opacity: 0.68
                                            }
                                        }
                                    }

                                    SettingsInsetPanel {
                                        width: parent.width
                                        visible: (settingsView.aniListInspectorEntries || []).length > 0
                                        tintColor: settingsView.effectiveAniListInspectorFilter === "attention"
                                            ? Color.mError
                                            : (settingsView.effectiveAniListInspectorFilter === "synced"
                                                ? Color.mPrimary
                                                : Color.mSecondary)
                                        tintStrength: settingsView.effectiveAniListInspectorFilter === "attention" ? 0.06 : 0.05
                                        baseAlpha: 0.9
                                        contentSpacing: 10

                                        Text {
                                            text: "Latest AniList Sync"
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: Color.mOnSurface
                                        }

                                        Text {
                                            width: parent.width
                                            text: settingsView._aniListInspectorSummary()
                                            wrapMode: Text.Wrap
                                            lineHeight: 1.35
                                            font.pixelSize: 10
                                            color: Color.mOnSurfaceVariant
                                            opacity: 0.74
                                        }

                                        Flow {
                                            width: parent.width
                                            spacing: 8

                                            Repeater {
                                                model: [
                                                    {
                                                        key: "attention",
                                                        label: "Attention " + String(settingsView.aniListInspectorCounts.attention || 0)
                                                    },
                                                    {
                                                        key: "synced",
                                                        label: "Synced " + String(settingsView.aniListInspectorCounts.synced || 0)
                                                    },
                                                    {
                                                        key: "unchanged",
                                                        label: "Unchanged " + String(settingsView.aniListInspectorCounts.unchanged || 0)
                                                    }
                                                ]

                                                delegate: SettingChoiceButton {
                                                    text: modelData.label
                                                    active: settingsView.effectiveAniListInspectorFilter === modelData.key
                                                    minWidth: 94
                                                    controlHeight: 30
                                                    fontPixelSize: 11
                                                    onClicked: settingsView.aniListInspectorFilter = modelData.key
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: parent.width
                                            radius: 16
                                            color: settingsView.effectiveAniListInspectorFilter === "attention"
                                                ? settingsView._malToneFill("error")
                                                : (settingsView.effectiveAniListInspectorFilter === "synced"
                                                    ? settingsView._malToneFill("primary")
                                                    : settingsView._malToneFill())
                                            border.width: 1
                                            border.color: settingsView.effectiveAniListInspectorFilter === "attention"
                                                ? settingsView._malToneBorder("error")
                                                : (settingsView.effectiveAniListInspectorFilter === "synced"
                                                    ? settingsView._malToneBorder("primary")
                                                    : settingsView._malToneBorder())
                                            implicitHeight: aniListInspectorFocusColumn.implicitHeight + 18

                                            Column {
                                                id: aniListInspectorFocusColumn
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                spacing: 4

                                                Text {
                                                    text: settingsView._aniListInspectorSectionTitle()
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                    color: Color.mOnSurface
                                                }

                                                Text {
                                                    width: parent.width
                                                    text: settingsView._aniListInspectorSectionHint()
                                                    wrapMode: Text.Wrap
                                                    lineHeight: 1.35
                                                    font.pixelSize: 10
                                                    color: Color.mOnSurfaceVariant
                                                    opacity: 0.8
                                                }
                                            }
                                        }

                                        Column {
                                            width: parent.width
                                            spacing: 8

                                            Repeater {
                                                model: settingsView.filteredAniListInspectorEntries.slice(0, 8)

                                                delegate: Rectangle {
                                                    width: parent.width
                                                    radius: 16
                                                    color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.9)
                                                    border.width: 1
                                                    border.color: _withAlpha(_outlineVariantColor(), 0.34)
                                                    implicitHeight: aniListInspectorEntryColumn.implicitHeight + 18

                                                    Column {
                                                        id: aniListInspectorEntryColumn
                                                        anchors.fill: parent
                                                        anchors.margins: 10
                                                        spacing: 6

                                                        Row {
                                                            width: parent.width
                                                            spacing: 8

                                                            Rectangle {
                                                                id: aniListInspectorStatusChip
                                                                width: aniListInspectorStatusLabel.implicitWidth + 16
                                                                height: 24
                                                                radius: 12
                                                                color: settingsView._malToneFill(modelData.badgeTone, true)
                                                                border.width: 1
                                                                border.color: settingsView._malToneBorder(modelData.badgeTone)

                                                                Text {
                                                                    id: aniListInspectorStatusLabel
                                                                    anchors.centerIn: parent
                                                                    text: modelData.badge?.label || ""
                                                                    font.pixelSize: 10
                                                                    font.bold: true
                                                                    color: settingsView._malToneText(modelData.badgeTone)
                                                                }
                                                            }

                                                            Text {
                                                                width: Math.max(0, parent.width - aniListInspectorStatusChip.width - 12)
                                                                text: modelData.title || "Untitled"
                                                                elide: Text.ElideRight
                                                                font.pixelSize: 11
                                                                font.bold: true
                                                                color: Color.mOnSurface
                                                            }
                                                        }

                                                        Text {
                                                            width: parent.width
                                                            visible: String(settingsView._aniListInspectorMetaText(modelData)).length > 0
                                                            wrapMode: Text.Wrap
                                                            lineHeight: 1.3
                                                            font.pixelSize: 10
                                                            color: Color.mOnSurfaceVariant
                                                            opacity: 0.78
                                                            text: settingsView._aniListInspectorMetaText(modelData)
                                                        }

                                                        Text {
                                                            width: parent.width
                                                            visible: String(modelData.detail || "").length > 0
                                                            wrapMode: Text.Wrap
                                                            lineHeight: 1.3
                                                            font.pixelSize: 10
                                                            color: Color.mOnSurfaceVariant
                                                            opacity: 0.72
                                                            text: modelData.detail || ""
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            visible: settingsView.filteredAniListInspectorEntries.length === 0
                                            width: parent.width
                                            text: settingsView._aniListInspectorEmptyText()
                                            wrapMode: Text.Wrap
                                            lineHeight: 1.35
                                            font.pixelSize: 10
                                            color: Color.mOnSurfaceVariant
                                            opacity: 0.72
                                        }

                                        Text {
                                            readonly property int extraCount:
                                                Math.max(0, settingsView.filteredAniListInspectorEntries.length - 8)
                                            visible: extraCount > 0
                                            text: "+" + String(extraCount) + " more title"
                                                + (extraCount === 1 ? "" : "s")
                                                + " in " + settingsView._aniListInspectorSectionTitle().toLowerCase()
                                            font.pixelSize: 10
                                            color: Color.mOnSurfaceVariant
                                            opacity: 0.72
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SettingsCard {
                        width: parent.width
                        tintColor: anime?.malSync?.enabled ? Color.mTertiary : Color.mPrimary
                        tintStrength: anime?.malSync?.enabled ? 0.09 : 0.07

                        Column {
                            id: malSection
                            width: parent.width
                            spacing: 14

                            RowLayout {
                                width: parent.width
                                spacing: 10

                                Rectangle {
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.12)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "M"
                                        font.pixelSize: 12
                                        font.bold: true
                                        color: Color.mPrimary
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: "MyAnimeList Sync"
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: Color.mOnSurface
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Keep AniList as the in-app metadata source and use MyAnimeList only for account sync. Regular login happens in the browser and AnimeReloaded finishes the connection automatically."
                                        wrapMode: Text.Wrap
                                        lineHeight: 1.35
                                        font.pixelSize: 11
                                        color: Color.mOnSurfaceVariant
                                        opacity: 0.76
                                    }
                                }
                            }

                            Flow {
                                width: parent.width
                                spacing: 8

                                SummaryPill {
                                    label: settingsView._malConnectionSummary()
                                    maxWidth: settingsView.wideLayout ? 320 : Math.max(180, parent.width - 12)
                                    toneColor: anime?.malSync?.enabled ? Color.mTertiary : Color.mPrimary
                                    textColor: anime?.malSync?.enabled ? Color.mTertiary : Color.mOnSurface
                                }

                                SummaryPill {
                                    label: anime?.malSync?.autoPush ? "Auto Push enabled" : "Manual push"
                                    toneColor: anime?.malSync?.autoPush ? Color.mPrimary : Color.mOnSurfaceVariant
                                    textColor: anime?.malSync?.autoPush ? Color.mPrimary : Color.mOnSurfaceVariant
                                }
                            }

                            Rectangle {
                                width: parent.width
                                radius: 18
                                color: settingsView._cardFill(
                                    anime?.malSync?.enabled ? Color.mTertiary : Color.mPrimary,
                                    anime?.malSync?.enabled ? 0.08 : 0.06,
                                    0.92
                                )
                                border.width: 1
                                border.color: settingsView._cardBorder(
                                    anime?.malSync?.enabled ? Color.mTertiary : Color.mPrimary,
                                    0.16
                                )
                                implicitHeight: malStatusColumn.implicitHeight + 22

                                Column {
                                    id: malStatusColumn
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    SettingsInsetPanel {
                                        width: parent.width
                                        tintColor: anime?.malSync?.enabled ? Color.mTertiary : Color.mPrimary
                                        tintStrength: anime?.malSync?.enabled ? 0.08 : 0.05
                                        baseAlpha: 0.92
                                        contentSpacing: 10

                                        RowLayout {
                                            width: parent.width
                                            spacing: 12

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Text {
                                                    text: "Connection"
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                    color: Color.mOnSurface
                                                }

                                                Flow {
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    Rectangle {
                                                        width: statusLabel.implicitWidth + 18
                                                        height: 26
                                                        radius: 13
                                                        color: anime?.malSync?.enabled
                                                            ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.16)
                                                            : Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.8)
                                                        border.width: 1
                                                        border.color: anime?.malSync?.enabled
                                                            ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.42)
                                                            : _withAlpha(_outlineVariantColor(), 0.4)

                                                        Text {
                                                            id: statusLabel
                                                            anchors.centerIn: parent
                                                            text: anime?.malSync?.enabled
                                                                ? ("Connected" + (anime?.malSync?.userName ? " · " + anime.malSync.userName : ""))
                                                                : "Not Connected"
                                                            font.pixelSize: 11
                                                            font.bold: true
                                                            color: anime?.malSync?.enabled ? Color.mPrimary : Color.mOnSurface
                                                        }
                                                    }

                                                    Rectangle {
                                                        width: autoPushLabel.implicitWidth + 18
                                                        height: 26
                                                        radius: 13
                                                        color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.82)
                                                        border.width: 1
                                                        border.color: _withAlpha(_outlineVariantColor(), 0.38)

                                                        Text {
                                                            id: autoPushLabel
                                                            anchors.centerIn: parent
                                                            text: anime?.malSync?.autoPush ? "Auto Push On" : "Auto Push Off"
                                                            font.pixelSize: 11
                                                            color: Color.mOnSurfaceVariant
                                                        }
                                                    }
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: anime?.malSync?.lastSyncAt
                                                        ? ("Last " + (anime?.malSync?.lastSyncDirection || "sync") + " · " + new Date(Number(anime.malSync.lastSyncAt) * 1000).toLocaleString())
                                                        : "No successful MyAnimeList sync yet."
                                                    wrapMode: Text.Wrap
                                                    font.pixelSize: 11
                                                    color: Color.mOnSurfaceVariant
                                                    opacity: 0.74
                                                }
                                            }

                                            Flow {
                                                Layout.alignment: Qt.AlignRight | Qt.AlignTop
                                                spacing: 8

                                                ActionChip {
                                                    text: anime?.malSync?.enabled ? "Reconnect MAL" : "Connect MAL"
                                                    leadingText: "M"
                                                    enabled: !(anime?.isMalSyncBusy ?? false)
                                                    onClicked: if (anime) anime.startMalBrowserAuth()
                                                }

                                                ActionChip {
                                                    text: "Disconnect"
                                                    leadingText: "✕"
                                                    visible: anime?.malSync?.enabled ?? false
                                                    enabled: (anime?.malSync?.enabled ?? false)
                                                        && !(anime?.isMalSyncBusy ?? false)
                                                    baseColor: Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.86)
                                                    hoverColor: Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.18)
                                                    hoverBorderColor: Qt.rgba(Color.mError.r, Color.mError.g, Color.mError.b, 0.4)
                                                    hoverTextColor: Color.mError
                                                    onClicked: if (anime) anime.clearMalSyncSession()
                                                }
                                            }
                                        }

                                        Text {
                                            visible: (anime?.malSyncMessage || "").length > 0
                                            width: parent.width
                                            text: anime?.malSyncMessage || ""
                                            wrapMode: Text.Wrap
                                            font.pixelSize: 11
                                            color: Color.mPrimary
                                        }

                                        Text {
                                            visible: (anime?.malSyncError || "").length > 0
                                            width: parent.width
                                            text: anime?.malSyncError || ""
                                            wrapMode: Text.Wrap
                                            font.pixelSize: 11
                                            color: Color.mError
                                        }
                                    }

                                    GridLayout {
                                        width: parent.width
                                        columns: settingsView.wideLayout ? 2 : 1
                                        columnSpacing: 12
                                        rowSpacing: 12

                                        SettingsInsetPanel {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignTop
                                            tintColor: Color.mPrimary
                                            tintStrength: 0.05
                                            baseAlpha: 0.9
                                            contentSpacing: 8

                                            Text {
                                                text: "Sync Mode"
                                                font.pixelSize: 11
                                                font.bold: true
                                                color: Color.mOnSurface
                                            }

                                            Text {
                                                width: parent.width
                                                text: "Choose whether local progress should wait for a manual push or sync out automatically."
                                                wrapMode: Text.Wrap
                                                lineHeight: 1.35
                                                font.pixelSize: 10
                                                color: Color.mOnSurfaceVariant
                                                opacity: 0.72
                                            }

                                            Flow {
                                                width: parent.width
                                                spacing: 10

                                                Repeater {
                                                    model: [
                                                        { label: "Manual", value: false },
                                                        { label: "Auto Push", value: true }
                                                    ]

                                                    delegate: SettingChoiceButton {
                                                        text: modelData.label
                                                        active: (anime?.malSync?.autoPush === true) === modelData.value
                                                        onClicked: if (anime) anime.setMalSyncField("autoPush", modelData.value)
                                                    }
                                                }
                                            }

                                            Text {
                                                width: parent.width
                                                text: anime?.malSync?.autoPush
                                                    ? "Auto Push sends local watch changes to MyAnimeList after a short delay. Pulls and imports never push back automatically."
                                                    : "Manual only updates MyAnimeList when you press Push To MAL."
                                                wrapMode: Text.Wrap
                                                lineHeight: 1.35
                                                font.pixelSize: 10
                                                color: Color.mOnSurfaceVariant
                                                opacity: 0.7
                                            }
                                        }

                                        SettingsInsetPanel {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignTop
                                            tintColor: anime?.malSync?.enabled ? Color.mTertiary : Color.mPrimary
                                            tintStrength: anime?.malSync?.enabled ? 0.06 : 0.05
                                            baseAlpha: 0.9
                                            contentSpacing: 8

                                            Text {
                                                text: "Sync Actions"
                                                font.pixelSize: 11
                                                font.bold: true
                                                color: Color.mOnSurface
                                            }

                                            Text {
                                                width: parent.width
                                                text: "Pull imports remote progress. Push sends your local progress back to MyAnimeList."
                                                wrapMode: Text.Wrap
                                                lineHeight: 1.35
                                                font.pixelSize: 10
                                                color: Color.mOnSurfaceVariant
                                                opacity: 0.72
                                            }

                                            Flow {
                                                width: parent.width
                                                spacing: 10

                                                ActionChip {
                                                    text: "Pull From MAL"
                                                    leadingText: "↓"
                                                    enabled: !(anime?.isMalSyncBusy ?? false)
                                                    onClicked: if (anime) anime.pullMalSync(true)
                                                }

                                                ActionChip {
                                                    text: "Push To MAL"
                                                    leadingText: "↑"
                                                    enabled: !(anime?.isMalSyncBusy ?? false)
                                                    onClicked: if (anime) anime.pushMalSync(true)
                                                }

                                            }

                                            Text {
                                                width: parent.width
                                                text: "Flow: click Connect MAL, approve access in the browser, then AnimeReloaded finishes the session automatically."
                                                wrapMode: Text.Wrap
                                                lineHeight: 1.35
                                                font.pixelSize: 10
                                                color: Color.mOnSurfaceVariant
                                                opacity: 0.68
                                            }
                                        }
                                    }

                                    SettingsInsetPanel {
                                        width: parent.width
                                        visible: (settingsView.malInspectorEntries || []).length > 0
                                        tintColor: settingsView.effectiveMalInspectorFilter === "attention"
                                            ? Color.mError
                                            : (settingsView.effectiveMalInspectorFilter === "ready"
                                                ? Color.mTertiary
                                                : Color.mPrimary)
                                        tintStrength: settingsView.effectiveMalInspectorFilter === "attention" ? 0.06 : 0.05
                                        baseAlpha: 0.9
                                        contentSpacing: 10

                                        Text {
                                            text: "Library Sync Status"
                                            font.pixelSize: 11
                                            font.bold: true
                                            color: Color.mOnSurface
                                        }

                                        Text {
                                            width: parent.width
                                            text: settingsView._malInspectorSummary()
                                            wrapMode: Text.Wrap
                                            lineHeight: 1.35
                                            font.pixelSize: 10
                                            color: Color.mOnSurfaceVariant
                                            opacity: 0.74
                                        }

                                        Flow {
                                            width: parent.width
                                            spacing: 8

                                            Repeater {
                                                model: [
                                                    {
                                                        key: "attention",
                                                        label: "Attention " + String(settingsView.malInspectorCounts.attention || 0)
                                                    },
                                                    {
                                                        key: "ready",
                                                        label: "Ready " + String(settingsView.malInspectorCounts.ready || 0)
                                                    },
                                                    {
                                                        key: "synced",
                                                        label: "Synced " + String(settingsView.malInspectorCounts.synced || 0)
                                                    }
                                                ]

                                                delegate: SettingChoiceButton {
                                                    text: modelData.label
                                                    active: settingsView.effectiveMalInspectorFilter === modelData.key
                                                    minWidth: 84
                                                    controlHeight: 30
                                                    fontPixelSize: 11
                                                    onClicked: settingsView.malInspectorFilter = modelData.key
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: parent.width
                                            radius: 16
                                            color: settingsView.effectiveMalInspectorFilter === "attention"
                                                ? settingsView._malToneFill("error")
                                                : (settingsView.effectiveMalInspectorFilter === "ready"
                                                    ? settingsView._malToneFill("accent")
                                                    : settingsView._malToneFill("primary"))
                                            border.width: 1
                                            border.color: settingsView.effectiveMalInspectorFilter === "attention"
                                                ? settingsView._malToneBorder("error")
                                                : (settingsView.effectiveMalInspectorFilter === "ready"
                                                    ? settingsView._malToneBorder("accent")
                                                    : settingsView._malToneBorder("primary"))
                                            implicitHeight: inspectorFocusColumn.implicitHeight + 18

                                            Column {
                                                id: inspectorFocusColumn
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                spacing: 4

                                                Text {
                                                    text: settingsView._malInspectorSectionTitle()
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                    color: Color.mOnSurface
                                                }

                                                Text {
                                                    width: parent.width
                                                    text: settingsView._malInspectorSectionHint()
                                                    wrapMode: Text.Wrap
                                                    lineHeight: 1.35
                                                    font.pixelSize: 10
                                                    color: Color.mOnSurfaceVariant
                                                    opacity: 0.8
                                                }
                                            }
                                        }

                                        Column {
                                            width: parent.width
                                            spacing: 8

                                            Repeater {
                                                model: settingsView.filteredMalInspectorEntries.slice(0, 8)

                                                delegate: Rectangle {
                                                    width: parent.width
                                                    radius: 16
                                                    color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.9)
                                                    border.width: 1
                                                    border.color: _withAlpha(_outlineVariantColor(), 0.34)
                                                    implicitHeight: inspectorEntryColumn.implicitHeight + 18

                                                    Column {
                                                        id: inspectorEntryColumn
                                                        anchors.fill: parent
                                                        anchors.margins: 10
                                                        spacing: 6

                                                        Row {
                                                            width: parent.width
                                                            spacing: 8

                                                            Rectangle {
                                                                id: inspectorStatusChip
                                                                width: inspectorStatusLabel.implicitWidth + 16
                                                                height: 24
                                                                radius: 12
                                                                color: settingsView._malToneFill(modelData.badgeTone, true)
                                                                border.width: 1
                                                                border.color: settingsView._malToneBorder(modelData.badgeTone)

                                                                Text {
                                                                    id: inspectorStatusLabel
                                                                    anchors.centerIn: parent
                                                                    text: modelData.badge?.label || ""
                                                                    font.pixelSize: 10
                                                                    font.bold: true
                                                                    color: settingsView._malToneText(modelData.badgeTone)
                                                                }
                                                            }

                                                            Text {
                                                                width: Math.max(0, parent.width - inspectorStatusChip.width - 12)
                                                                text: modelData.title || "Untitled"
                                                                elide: Text.ElideRight
                                                                font.pixelSize: 11
                                                                font.bold: true
                                                                color: Color.mOnSurface
                                                            }
                                                        }

                                                        Text {
                                                            width: parent.width
                                                            wrapMode: Text.Wrap
                                                            lineHeight: 1.3
                                                            font.pixelSize: 10
                                                            color: Color.mOnSurfaceVariant
                                                            opacity: 0.78
                                                            text: settingsView._malInspectorMetaText(modelData)
                                                        }

                                                        Text {
                                                            width: parent.width
                                                            visible: String(settingsView._malInspectorDetailText(modelData)).length > 0
                                                            wrapMode: Text.Wrap
                                                            lineHeight: 1.3
                                                            font.pixelSize: 10
                                                            color: Color.mOnSurfaceVariant
                                                            opacity: 0.72
                                                            text: settingsView._malInspectorDetailText(modelData)
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            visible: settingsView.filteredMalInspectorEntries.length === 0
                                            width: parent.width
                                            text: settingsView._malInspectorEmptyText()
                                            wrapMode: Text.Wrap
                                            lineHeight: 1.35
                                            font.pixelSize: 10
                                            color: Color.mOnSurfaceVariant
                                            opacity: 0.72
                                        }

                                        Text {
                                            readonly property int extraCount:
                                                Math.max(0, settingsView.filteredMalInspectorEntries.length - 8)
                                            visible: extraCount > 0
                                            text: "+" + String(extraCount) + " more title"
                                                + (extraCount === 1 ? "" : "s")
                                                + " in " + settingsView._malInspectorSectionTitle().toLowerCase()
                                            font.pixelSize: 10
                                            color: Color.mOnSurfaceVariant
                                            opacity: 0.72
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
