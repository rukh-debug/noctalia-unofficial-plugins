import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.System
import qs.Services.UI
import "MalStatus.js" as MalStatus
import "js/providers.js" as Providers

Item {
    id: root

    property var pluginApi: null
    readonly property var malSyncManifestConfig: {
        var config = pluginApi?.manifest?.metadata?.malSync
        return (config && typeof config === "object" && !Array.isArray(config))
            ? config
            : ({})
    }
    readonly property string defaultMalBackendUrl:
        String(malSyncManifestConfig.defaultBackendUrl || "").trim().replace(/\/+$/, "")
    readonly property var legacyMalBackendUrls: {
        var urls = malSyncManifestConfig.legacyBackendUrls
        if (!Array.isArray(urls))
            return []
        return urls
            .map(function(url) { return String(url || "").trim().replace(/\/+$/, "") })
            .filter(function(url, index, items) { return url.length > 0 && items.indexOf(url) === index })
    }
    readonly property string runtimeRoot:
        pluginApi?.manifest?.metadata?.runtimeRoot ?? ""
    readonly property string defaultAniListRedirectUri:
        "https://anilist.co/api/v2/oauth/pin"
    readonly property int librarySchemaVersion: 2

    function _pathJoin(base, child) {
        if (!base || base.length === 0)
            return child || ""
        if (!child || child.length === 0)
            return base
        if (base.endsWith("/"))
            return base + child
        return base + "/" + child
    }

    function _runtimePath(relativePath) {
        return _pathJoin(_pathJoin(pluginApi?.pluginDir ?? "", runtimeRoot), relativePath)
    }

    readonly property string luaPath:
        _runtimePath("progress.lua")
    readonly property string progressDir:
        _pathJoin(pluginApi?.pluginDir ?? "", "progress")

    // ── Settings ──────────────────────────────────────────────────────────────
    property string currentMode:
        pluginApi?.pluginSettings?.mode ||
        pluginApi?.manifest?.metadata?.defaultSettings?.mode ||
        "sub"

    property string panelSize:  pluginApi?.pluginSettings?.panelSize  || "medium"
    property string posterSize: pluginApi?.pluginSettings?.posterSize || "medium"
    property string preferredProvider: pluginApi?.pluginSettings?.preferredProvider || "auto"
    property bool   enableStartupFeedToast:
        pluginApi?.pluginSettings?.enableStartupFeedToast !== false
    property string metadataProviderId:
        pluginApi?.pluginSettings?.metadataProvider ||
        pluginApi?.manifest?.metadata?.defaultSettings?.metadataProvider ||
        pluginApi?.manifest?.metadata?.providers?.metadata?.default ||
        "allanime"
    property string streamProviderId:
        pluginApi?.pluginSettings?.streamProvider ||
        pluginApi?.manifest?.metadata?.defaultSettings?.streamProvider ||
        pluginApi?.manifest?.metadata?.providers?.stream?.default ||
        "allanime"
    property var    aniListSync: _normaliseAniListSync(pluginApi?.pluginSettings?.aniListSync)
    property var    malSync: _normaliseMalSync(pluginApi?.pluginSettings?.malSync)
    property var    browseCache: ({})
    property var    detailCache: ({})
    property bool   panelSettingsOpen: false
    property string aniListAuthDraft: ""

    function _preferredPanelScreen() {
        if (pluginApi?.panelOpenScreen)
            return pluginApi.panelOpenScreen
        var screens = Quickshell.screens || []
        if (!screens || screens.length === 0)
            return null
        for (var i = 0; i < screens.length; i++) {
            var screen = screens[i]
            if (screen && screen.x === 0 && screen.y === 0)
                return screen
        }
        return screens[0]
    }

    function _normalisePosterSize(nextPanelSize, nextPosterSize) {
        if (nextPanelSize === "small" && nextPosterSize === "small")
            return "medium"
        return nextPosterSize
    }

    function _deepClone(value) {
        if (value === null || value === undefined)
            return value
        try {
            return JSON.parse(JSON.stringify(value))
        } catch (e) {
            return value
        }
    }

    function _isObject(value) {
        return value !== null && value !== undefined
            && typeof value === "object" && !Array.isArray(value)
    }

    function _inferMetadataProviderFromId(metadataId) {
        var resolvedId = String(metadataId || "").trim()
        if (resolvedId.length === 0)
            return ""
        if (/^\d+$/.test(resolvedId))
            return "anilist"
        return "allanime"
    }

    function _migrateLibraryEntrySchema(entry) {
        var item = _deepClone(entry || {})
        if (!_isObject(item))
            item = ({})

        var changed = false

        if (!_isObject(item.providerRefs)) {
            item.providerRefs = ({})
            changed = true
        } else {
            item.providerRefs = _deepClone(item.providerRefs)
        }

        var metadataRef = _isObject(item.providerRefs.metadata)
            ? _deepClone(item.providerRefs.metadata)
            : ({})
        var resolvedMetadataId = String(metadataRef.id || item.id || "").trim()
        var resolvedMetadataProvider = String(metadataRef.provider || "").trim()
        if ((resolvedMetadataProvider !== "anilist" && resolvedMetadataProvider !== "allanime")
                && resolvedMetadataId.length > 0)
            resolvedMetadataProvider = _inferMetadataProviderFromId(resolvedMetadataId)
        if (resolvedMetadataId.length > 0) {
            if (String(metadataRef.id || "") !== resolvedMetadataId
                    || String(metadataRef.provider || "") !== resolvedMetadataProvider)
                changed = true
            item.providerRefs.metadata = {
                provider: resolvedMetadataProvider,
                id: resolvedMetadataId
            }
            if (String(item.id || "").trim().length === 0) {
                item.id = resolvedMetadataId
                changed = true
            }
        } else if (item.providerRefs.metadata !== undefined) {
            delete item.providerRefs.metadata
            changed = true
        }

        if (_inferMetadataProviderFromId(resolvedMetadataId) === "allanime"
                && !_isObject(item.providerRefs.stream)
                && resolvedMetadataId.length > 0) {
            item.providerRefs.stream = {
                provider: "allanime",
                id: resolvedMetadataId
            }
            changed = true
        }

        var syncRef = _isObject(item.providerRefs.sync)
            ? _deepClone(item.providerRefs.sync)
            : ({})
        var syncId = String(syncRef.id || item.malId || "").trim()
        var syncProvider = "myanimelist"
        if (syncId.length > 0) {
            if (String(syncRef.id || "") !== syncId
                    || String(syncRef.provider || "") !== syncProvider)
                changed = true
            item.providerRefs.sync = {
                provider: syncProvider,
                id: syncId
            }
        } else if (item.providerRefs.sync !== undefined) {
            delete item.providerRefs.sync
            changed = true
        }

        if (item.malId !== undefined) {
            delete item.malId
            changed = true
        }

        return {
            entry: item,
            changed: changed
        }
    }

    function _migrateLibrarySchemaIfNeeded() {
        if (!pluginApi || !pluginApi.pluginSettings)
            return

        var currentVersion = Number(pluginApi.pluginSettings.librarySchemaVersion || 0)
        if (currentVersion >= librarySchemaVersion)
            return

        var rawLibrary = pluginApi.pluginSettings.library
        var migratedLibrary = []
        var changed = currentVersion !== librarySchemaVersion
        if (Array.isArray(rawLibrary)) {
            for (var i = 0; i < rawLibrary.length; i++) {
                var migrated = _migrateLibraryEntrySchema(rawLibrary[i])
                migratedLibrary.push(migrated.entry)
                if (migrated.changed)
                    changed = true
            }
        } else if (rawLibrary !== undefined) {
            changed = true
        }

        if (changed && Array.isArray(rawLibrary))
            pluginApi.pluginSettings.library = migratedLibrary
        else if (!Array.isArray(rawLibrary) && rawLibrary !== undefined)
            pluginApi.pluginSettings.library = []

        pluginApi.pluginSettings.librarySchemaVersion = librarySchemaVersion
        pluginApi.saveSettings()
    }

    function _isVisibleGenre(genre) {
        var name = String(genre || "").trim()
        if (name.length === 0)
            return false
        return name.toLowerCase() !== "ecchi" && name.toLowerCase() !== "hentai"
    }

    function _filterVisibleGenres(genres) {
        var filtered = []
        var seen = ({})
        var items = Array.isArray(genres) ? genres : []
        for (var i = 0; i < items.length; i++) {
            var name = String(items[i] || "").trim()
            if (!_isVisibleGenre(name))
                continue
            var key = name.toLowerCase()
            if (seen[key])
                continue
            seen[key] = true
            filtered.push(name)
        }
        return filtered
    }

    function _entryRepairKey(entry) {
        return [
            _showMetadataProviderId(entry),
            _showMetadataId(entry),
            String(entry?.id || "")
        ].join("\u241f")
    }

    IpcHandler {
        target: "plugin:AnimeReloaded"

        function openPanel() {
            if (pluginApi) {
                pluginApi.withCurrentScreen(function(screen) {
                    pluginApi.openPanel(screen)
                })
            }
        }

        function closePanel() {
            if (pluginApi) {
                var screen = root._preferredPanelScreen()
                if (screen)
                    pluginApi.closePanel(screen)
            }
        }

        function togglePanel() {
            if (pluginApi) {
                pluginApi.withCurrentScreen(function(screen) {
                    pluginApi.togglePanel(screen)
                })
            }
        }

        function openPanelOnPrimary() {
            if (pluginApi) {
                var screen = root._preferredPanelScreen()
                if (screen)
                    pluginApi.openPanel(screen)
            }
        }
    }

    function _emptyFeedNotificationState() {
        return {
            version: 1,
            media: ({})
        }
    }

    function _emptyAniListSync() {
        return {
            version: 1,
            enabled: false,
            autoPush: false,
            clientId: "",
            redirectUri: defaultAniListRedirectUri,
            accessToken: "",
            userId: 0,
            userName: "",
            userPicture: "",
            lastSyncAt: 0,
            lastSyncDirection: ""
        }
    }

    function _emptyMalSync() {
        return {
            version: 2,
            enabled: false,
            autoPush: false,
            backendUrl: defaultMalBackendUrl,
            backendAuthSessionId: "",
            backendSessionToken: "",
            userName: "",
            userPicture: "",
            lastSyncAt: 0,
            lastSyncDirection: ""
        }
    }

    function _normaliseAniListSync(raw) {
        var source = _deepClone(raw)
        if (!source || typeof source !== "object" || Array.isArray(source))
            source = ({})
        var config = _emptyAniListSync()
        config.enabled = source.enabled === true
        config.autoPush = source.autoPush === true
        config.clientId = String(source.clientId || "").trim()
        config.redirectUri = defaultAniListRedirectUri
        config.accessToken = String(source.accessToken || "").trim()
        config.userId = Number(source.userId || 0)
        config.userName = String(source.userName || "")
        config.userPicture = String(source.userPicture || "")
        config.lastSyncAt = Number(source.lastSyncAt || 0)
        config.lastSyncDirection = String(source.lastSyncDirection || "")
        return config
    }

    function _normaliseMalSync(raw) {
        var source = _deepClone(raw)
        if (!source || typeof source !== "object" || Array.isArray(source))
            source = ({})
        var config = _emptyMalSync()
        config.enabled = source.enabled === true
        config.autoPush = source.autoPush === true
        var backendUrl = String(source.backendUrl || "").trim().replace(/\/+$/, "")
        if (backendUrl.length === 0 || legacyMalBackendUrls.indexOf(backendUrl) >= 0)
            backendUrl = defaultMalBackendUrl
        config.backendUrl = backendUrl
        config.backendAuthSessionId = String(source.backendAuthSessionId || "")
        config.backendSessionToken = String(source.backendSessionToken || "")
        config.userName = String(source.userName || "")
        config.userPicture = String(source.userPicture || "")
        config.lastSyncAt = Number(source.lastSyncAt || 0)
        config.lastSyncDirection = String(source.lastSyncDirection || "")
        return config
    }

    function _normaliseFeedNotificationState(raw) {
        var state = _deepClone(raw)
        if (!state || typeof state !== "object" || Array.isArray(state))
            state = _emptyFeedNotificationState()
        if (!state.media || typeof state.media !== "object" || Array.isArray(state.media))
            state.media = ({})
        state.version = 1
        return state
    }

    function _loadFeedNotificationState() {
        feedNotificationState = _normaliseFeedNotificationState(pluginApi?.pluginSettings?.feedNotificationState)
    }

    function _saveFeedNotificationState() {
        if (!pluginApi) return
        pluginApi.pluginSettings.feedNotificationState = _deepClone(feedNotificationState)
        pluginApi.saveSettings()
    }

    function _saveAniListSyncSettings() {
        if (!pluginApi) return
        pluginApi.pluginSettings.aniListSync = _deepClone(aniListSync)
        pluginApi.saveSettings()
    }

    function _saveMalSyncSettings() {
        if (!pluginApi) return
        pluginApi.pluginSettings.malSync = _deepClone(malSync)
        pluginApi.saveSettings()
    }

    function setAniListSyncField(key, value) {
        var next = _normaliseAniListSync(aniListSync)
        next[key] = value
        aniListSync = _normaliseAniListSync(next)
        _saveAniListSyncSettings()
    }

    function updateAniListSyncConfig(config) {
        aniListSync = _normaliseAniListSync(config)
        _saveAniListSyncSettings()
    }

    function setMalSyncField(key, value) {
        var next = _normaliseMalSync(malSync)
        next[key] = value
        malSync = _normaliseMalSync(next)
        _saveMalSyncSettings()
    }

    function updateMalSyncConfig(config) {
        malSync = _normaliseMalSync(config)
        _saveMalSyncSettings()
    }

    function clearAniListSyncSession() {
        aniListAutoPushTimer.stop()
        var next = _normaliseAniListSync(aniListSync)
        next.enabled = false
        next.accessToken = ""
        next.userId = 0
        next.userName = ""
        next.userPicture = ""
        next.lastSyncAt = 0
        next.lastSyncDirection = ""
        updateAniListSyncConfig(next)
        aniListSyncError = ""
        aniListSyncMessage = "Disconnected from AniList."
        aniListSyncSummary = ({})
        aniListSyncResults = []
        aniListAuthDraft = ""
        _pendingAniListCommand = ""
        _pendingAniListBrowserAuth = false
    }

    function clearMalSyncSession() {
        malAutoPushTimer.stop()
        var next = _normaliseMalSync(malSync)
        next.enabled = false
        next.backendAuthSessionId = ""
        next.backendSessionToken = ""
        next.userName = ""
        next.userPicture = ""
        next.lastSyncAt = 0
        next.lastSyncDirection = ""
        updateMalSyncConfig(next)
        malSyncError = ""
        malSyncMessage = "Disconnected from MyAnimeList."
        malSyncSummary = ({})
        malSyncResults = []
        _pendingMalBrowserAuth = false
        _pendingMalBrowserAuthUrl = ""
    }

    function _entryCountLabel(count) {
        var value = Number(count || 0)
        return String(value) + " entr" + (value === 1 ? "y" : "ies")
    }

    function _formatMalSyncMessage(direction, summary) {
        var info = summary || ({})
        var updated = Number(info.updated || 0)
        var imported = Number(info.imported || 0)
        var removed = Number(info.removed || 0)
        var skipped = Number(info.skipped || 0)
        var failed = Number(info.failed || 0)
        var suffix = ""
        if (skipped > 0 || failed > 0) {
            var parts = []
            if (skipped > 0)
                parts.push(String(skipped) + " skipped")
            if (failed > 0)
                parts.push(String(failed) + " failed")
            suffix = " " + parts.join(", ") + "."
        }

        if (direction === "push") {
            if (updated <= 0 && failed <= 0)
                return "MyAnimeList is already in sync." + suffix
            return "Pushed " + _entryCountLabel(updated) + " to MyAnimeList." + suffix
        }

        if (direction === "pull") {
            if (updated <= 0 && imported <= 0 && failed <= 0)
                return "MyAnimeList is already in sync." + suffix
            if (updated > 0 && imported > 0)
                return "Pulled " + _entryCountLabel(updated) + " and imported " + _entryCountLabel(imported) + " from MyAnimeList." + suffix
            if (imported > 0)
                return "Imported " + _entryCountLabel(imported) + " from MyAnimeList." + suffix
            return "Pulled " + _entryCountLabel(updated) + " from MyAnimeList." + suffix
        }

        if (direction === "delete") {
            if (removed <= 0 && failed <= 0)
                return "MyAnimeList entry was not removed." + suffix
            return "Removed " + _entryCountLabel(removed) + " from MyAnimeList." + suffix
        }

        return "MyAnimeList sync completed." + suffix
    }

    function _formatAniListSyncMessage(direction, summary) {
        var info = summary || ({})
        var updated = Number(info.updated || 0)
        var imported = Number(info.imported || 0)
        var removed = Number(info.removed || 0)
        var skipped = Number(info.skipped || 0)
        var failed = Number(info.failed || 0)
        var suffix = ""
        if (skipped > 0 || failed > 0) {
            var parts = []
            if (skipped > 0)
                parts.push(String(skipped) + " skipped")
            if (failed > 0)
                parts.push(String(failed) + " failed")
            suffix = " " + parts.join(", ") + "."
        }

        if (direction === "push") {
            if (updated <= 0 && failed <= 0)
                return "AniList is already in sync." + suffix
            return "Pushed " + _entryCountLabel(updated) + " to AniList." + suffix
        }

        if (direction === "pull") {
            if (updated <= 0 && imported <= 0 && failed <= 0)
                return "AniList is already in sync." + suffix
            if (updated > 0 && imported > 0)
                return "Pulled " + _entryCountLabel(updated) + " and imported " + _entryCountLabel(imported) + " from AniList." + suffix
            if (imported > 0)
                return "Imported " + _entryCountLabel(imported) + " from AniList." + suffix
            return "Pulled " + _entryCountLabel(updated) + " from AniList." + suffix
        }

        if (direction === "delete") {
            if (removed <= 0 && failed <= 0)
                return "AniList entry was not removed." + suffix
            return "Removed " + _entryCountLabel(removed) + " from AniList." + suffix
        }

        return "AniList sync completed." + suffix
    }

    function _syncNotificationCommandLabel(command) {
        var key = String(command || "").trim().toLowerCase()
        if (key === "push")
            return "Push"
        if (key === "pull")
            return "Pull"
        if (key === "delete-entry" || key === "delete")
            return "Removal"
        if (key === "connect-token")
            return "Connection"
        if (key === "refresh")
            return "Refresh"
        if (key === "auth-url")
            return "Login"
        return "Sync"
    }

    function _syncNotificationFactLines(summary) {
        var info = summary || ({})
        var counts = [
            { label: "Updated", value: Number(info.updated || 0) },
            { label: "Imported", value: Number(info.imported || 0) },
            { label: "Removed", value: Number(info.removed || 0) },
            { label: "Skipped", value: Number(info.skipped || 0) },
            { label: "Failed", value: Number(info.failed || 0) }
        ]
        var lines = []
        for (var i = 0; i < counts.length; i++) {
            var item = counts[i]
            if (item.value > 0)
                lines.push(item.label + ": " + String(item.value))
        }
        return lines
    }

    function _syncNotificationResultLine(result) {
        var item = result || ({})
        var title = String(item.title || item.id || "Untitled")
        var reason = String(item.reason || "").trim()
        var status = String(item.status || "").trim().toLowerCase()
        if (reason.length > 0)
            return title + ": " + reason
        if (status === "updated")
            return title + ": synced successfully."
        if (status === "imported")
            return title + ": imported into the local library."
        if (status === "removed")
            return title + ": removed successfully."
        if (status === "unchanged")
            return title + ": already aligned."
        return title
    }

    function _syncNotificationBody(message, summary, results) {
        var lines = []
        var text = String(message || "").trim()
        var factLines = _syncNotificationFactLines(summary)
        var issues = (results || []).filter(function(item) {
            var status = String((item || {}).status || "").trim().toLowerCase()
            return status === "error" || status === "skipped"
        }).slice(0, 5)
        var successes = (results || []).filter(function(item) {
            var status = String((item || {}).status || "").trim().toLowerCase()
            return status === "updated" || status === "imported" || status === "removed"
        }).slice(0, 3)

        if (text.length > 0)
            lines.push(text)
        if (factLines.length > 0) {
            if (lines.length > 0)
                lines.push("")
            lines = lines.concat(factLines)
        }
        if (issues.length > 0) {
            if (lines.length > 0)
                lines.push("")
            lines.push("Issues:")
            for (var i = 0; i < issues.length; i++)
                lines.push("- " + _syncNotificationResultLine(issues[i]))
        } else if (successes.length > 0) {
            if (lines.length > 0)
                lines.push("")
            lines.push("Recent changes:")
            for (var j = 0; j < successes.length; j++)
                lines.push("- " + _syncNotificationResultLine(successes[j]))
        }

        return lines.join("\n")
    }

    function _logSyncNotification(serviceName, command, message, summary, results, isError) {
        var title = String(serviceName || "Sync") + " " + _syncNotificationCommandLabel(command)
        var body = _syncNotificationBody(message, summary, results)
        if (body.length === 0)
            body = title
        NotificationService.addToHistory({
            id: "anime-reloaded-sync-" + String(Date.now()) + "-" + String(Math.random()).slice(2, 8),
            summary: title,
            summaryMarkdown: title,
            body: body,
            bodyMarkdown: body,
            appName: "AnimeReloaded",
            urgency: isError === true ? 2 : 1,
            expireTimeout: 0,
            timestamp: new Date(),
            originalImage: "",
            cachedImage: "",
            actionsJson: "[]",
            originalId: 0
        })
    }

    function _showSyncFeedback(serviceName, command, message, summary, results, showToast, isError) {
        if (!showToast)
            return
        ToastService.showNotice(
            "AnimeReloaded",
            String(message || ""),
            "device-tv",
            isError === true ? 4200 : 3200
        )
        _logSyncNotification(serviceName, command, message, summary, results, isError)
    }

    function _feedMediaId(item) {
        return String(item?.providerRefs?.metadata?.id || item?.mediaId || "")
    }

    function _feedReleasedEpisode(item) {
        return Number(item?.latestReleasedEpisode || item?.eventEpisode || 0)
    }

    function _feedStateEntry(state, mediaId, createIfMissing) {
        if (!mediaId) return null
        var mediaState = state?.media || ({})
        var entry = mediaState[mediaId]
        if (!entry && createIfMissing) {
            entry = {
                lastSeenEpisode: 0,
                lastToastEpisode: 0,
                lastKnownReleasedEpisode: 0
            }
            mediaState[mediaId] = entry
            state.media = mediaState
        }
        return entry || null
    }

    function _recomputeFeedUnreadCount(items, state) {
        var alerts = items || []
        var currentState = state || feedNotificationState || _emptyFeedNotificationState()
        var unread = 0
        for (var i = 0; i < alerts.length; i++) {
            var item = alerts[i]
            var mediaId = _feedMediaId(item)
            var latestEpisode = _feedReleasedEpisode(item)
            if (!mediaId || latestEpisode <= 0)
                continue
            var entry = _feedStateEntry(currentState, mediaId, false)
            var lastSeen = Number(entry?.lastSeenEpisode || 0)
            if (latestEpisode > lastSeen)
                unread++
        }
        feedUnreadCount = unread
    }

    function isFeedItemUnread(item) {
        var mediaId = _feedMediaId(item)
        var latestEpisode = _feedReleasedEpisode(item)
        if (!mediaId || latestEpisode <= 0)
            return false
        var entry = _feedStateEntry(feedNotificationState, mediaId, false)
        return latestEpisode > Number(entry?.lastSeenEpisode || 0)
    }

    function _applyFeedPayload(payload) {
        var alerts = payload?.results || []
        var upcoming = payload?.upcoming || []
        var summary = payload?.summary || ({
            alerts: alerts.length,
            upcoming: upcoming.length,
            following: alerts.length + upcoming.length
        })

        var state = _normaliseFeedNotificationState(feedNotificationState)
        var changed = false
        var toastCount = 0

        for (var i = 0; i < alerts.length; i++) {
            var item = alerts[i]
            var mediaId = _feedMediaId(item)
            var latestEpisode = _feedReleasedEpisode(item)
            if (!mediaId || latestEpisode <= 0)
                continue
            var entry = _feedStateEntry(state, mediaId, true)
            if (latestEpisode > Number(entry.lastKnownReleasedEpisode || 0)) {
                entry.lastKnownReleasedEpisode = latestEpisode
                changed = true
            }
            if (_pendingStartupFeedToast && latestEpisode > Number(entry.lastToastEpisode || 0))
                toastCount++
        }

        feedNotificationState = state
        feedList = alerts
        feedUpcomingList = upcoming
        feedSummary = summary
        feedError = ""
        feedLastFetchedAt = Date.now()

        if (_pendingStartupFeedToast) {
            if (toastCount > 0) {
                for (var j = 0; j < alerts.length; j++) {
                    var toastItem = alerts[j]
                    var toastMediaId = _feedMediaId(toastItem)
                    var toastEpisode = _feedReleasedEpisode(toastItem)
                    if (!toastMediaId || toastEpisode <= 0)
                        continue
                    var toastEntry = _feedStateEntry(feedNotificationState, toastMediaId, true)
                    if (toastEpisode > Number(toastEntry.lastToastEpisode || 0)) {
                        toastEntry.lastToastEpisode = toastEpisode
                        changed = true
                    }
                }
                if (enableStartupFeedToast) {
                    ToastService.showNotice(
                        "AnimeReloaded",
                        toastCount === 1 ? "1 new episode release in Feed" : (toastCount + " new episode releases in Feed"),
                        "device-tv",
                        4200
                    )
                }
            }
            _pendingStartupFeedToast = false
        }

        _recomputeFeedUnreadCount(alerts, feedNotificationState)
        if (changed)
            _saveFeedNotificationState()
    }

    function _browseCacheKey(args) {
        return args.join("\u241f")
    }

    function _detailCacheKey(show, mode) {
        return [
            _showMetadataProviderId(show),
            _showMetadataId(show),
            String(mode || "")
        ].join("\u241f")
    }

    function _showMetadataProviderId(show) {
        var explicitProvider = String(show?.providerRefs?.metadata?.provider || "")
        if (explicitProvider.length > 0)
            return explicitProvider
        var showId = String(show?.id || "")
        if ((metadataProviderId || "anilist") === "anilist" && !/^\d+$/.test(showId))
            return "allanime"
        return String(metadataProviderId || "anilist")
    }

    function _showMetadataId(show) {
        return String(show?.providerRefs?.metadata?.id || show?.id || "")
    }

    function _showAniListMediaId(show) {
        var metadataProvider = String(show?.providerRefs?.metadata?.provider || "")
        var metadataId = String(show?.providerRefs?.metadata?.id || "")
        if (metadataProvider === "anilist" && /^\d+$/.test(metadataId))
            return metadataId
        var showId = String(show?.id || "")
        if (/^\d+$/.test(showId))
            return showId
        return ""
    }

    function _showStreamProviderId(show) {
        return String(show?.providerRefs?.stream?.provider || streamProviderId || "allanime")
    }

    function _showTitle(show) {
        return String(show?.englishName || show?.name || "Untitled")
    }

    function _showMalId(show) {
        var syncRef = show?.providerRefs?.sync
        if (String(syncRef?.provider || "") === "myanimelist" && String(syncRef?.id || "").length > 0)
            return String(syncRef.id)
        if (String(show?.malId || "").length > 0)
            return String(show.malId)
        return ""
    }

    function _findMalSyncResult(show) {
        var malId = _showMalId(show)
        var metadataId = _showMetadataId(show)
        var results = malSyncResults || []
        for (var i = 0; i < results.length; i++) {
            var item = results[i] || ({})
            if (malId.length > 0 && String(item.malId || "") === malId)
                return item
            if (metadataId.length > 0 && String(item.id || "") === metadataId)
                return item
        }
        return null
    }

    function _normaliseMalListStatus(value) {
        return MalStatus.normaliseMalStatus(value)
    }

    function malListStatusLabel(value) {
        var status = _normaliseMalListStatus(value)
        if (status === "plan_to_watch")
            return "Plan To Watch"
        if (status === "watching")
            return "Watching"
        if (status === "completed")
            return "Completed"
        if (status === "on_hold")
            return "On Hold"
        if (status === "dropped")
            return "Dropped"
        return ""
    }

    function _malResultFacts(result) {
        var parts = []
        var watched = Number(result?.watchedEpisodes || 0)
        var remoteStatus = malListStatusLabel(result?.remoteStatus)
        if (remoteStatus.length > 0)
            parts.push("Status: " + remoteStatus + ".")
        if (watched > 0)
            parts.push("Watched on MAL: " + watched + " episode" + (watched === 1 ? "" : "s") + ".")
        return parts.join(" ")
    }

    function _malResultDetail(baseDetail, result) {
        var facts = _malResultFacts(result)
        if (facts.length === 0)
            return String(baseDetail || "")
        return String(baseDetail || "") + " " + facts
    }

    function _showLocalWatchedEpisodes(show) {
        var watched = Number(show?.lastWatchedEpNum || 0)
        var watchedEpisodes = show?.watchedEpisodes
        if (Array.isArray(watchedEpisodes))
            watched = Math.max(watched, watchedEpisodes.length)
        return watched
    }

    function _entryHasSavedProgress(entry) {
        var progress = entry?.episodeProgress || {}
        var keys = Object.keys(progress)
        for (var i = 0; i < keys.length; i++) {
            if (_progressPosition(progress[keys[i]]) > 0)
                return true
        }
        return false
    }

    function _entryWatchedEpisodesForStatus(entry) {
        var watched = _showLocalWatchedEpisodes(entry)
        if (watched <= 0 && _entryHasSavedProgress(entry))
            watched = 1
        return watched
    }

    function resolveAnimeStatus(input) {
        return MalStatus.resolveAnimeStatus(input || ({}))
    }

    function updateAnimeStatus(input) {
        return MalStatus.updateAnimeStatus(input || ({}))
    }

    function buildMalPayload(animeId, status, watchedEpisodes) {
        return MalStatus.buildMalPayload(animeId, status, watchedEpisodes)
    }

    function _resolvedLibraryStatus(entry, userAction) {
        return resolveAnimeStatus({
            currentStatus: _normaliseMalListStatus(entry?.listStatus),
            watchedEpisodes: _entryWatchedEpisodesForStatus(entry),
            totalEpisodes: Number(entry?.episodeCount || 0),
            userAction: userAction || null
        })
    }

    function libraryListStatus(entry) {
        return _resolvedLibraryStatus(entry, null).status
    }

    function libraryListStatusState(entry) {
        var key = libraryListStatus(entry)
        return {
            key: key,
            label: malListStatusLabel(key) || "Plan To Watch"
        }
    }

    function _malSyncBadgeData(show, compact, includeWhenDisconnected) {
        var isCompact = compact === true
        if (!_malSyncReady() && includeWhenDisconnected !== true) {
            return {
                visible: false,
                key: "disabled",
                tone: "muted",
                label: "",
                detail: ""
            }
        }

        var malId = _showMalId(show)
        if (malId.length === 0) {
            return {
                visible: true,
                key: "unmapped",
                tone: "muted",
                label: isCompact ? "MAL ?" : "MAL Unmapped",
                detail: "No MyAnimeList mapping is available for this title yet."
            }
        }

        var result = _findMalSyncResult(show)
        if (!result) {
            return {
                visible: true,
                key: "linked",
                tone: "primary",
                label: isCompact ? "MAL" : "MAL Ready",
                detail: "Mapped to MyAnimeList and ready for pull, push, or removal."
            }
        }

        var status = String(result.status || "").toLowerCase()
        if (status === "error") {
            return {
                visible: true,
                key: "error",
                tone: "error",
                label: isCompact ? "MAL !" : "MAL Error",
                detail: String(result.reason || "The latest MyAnimeList sync failed for this title.")
            }
        }
        if (status === "skipped") {
            return {
                visible: true,
                key: "skipped",
                tone: "muted",
                label: isCompact ? "MAL -" : "MAL Skipped",
                detail: String(result.reason || "The latest MyAnimeList sync skipped this title.")
            }
        }
        if (status === "removed") {
            return {
                visible: true,
                key: "removed",
                tone: "error",
                label: isCompact ? "MAL x" : "Removed From MAL",
                detail: "This title was removed from your MyAnimeList list in the latest sync action."
            }
        }
        if (status === "imported") {
            return {
                visible: true,
                key: "imported",
                tone: "accent",
                label: isCompact ? "MAL +" : "Imported From MAL",
                detail: _malResultDetail(
                    "This title was imported from your MyAnimeList list.",
                    result
                )
            }
        }
        return {
            visible: true,
            key: "synced",
            tone: "primary",
            label: isCompact ? "MAL ✓" : "MAL Synced",
            detail: _malResultDetail(
                status === "updated"
                    ? "The latest MyAnimeList sync updated this title successfully."
                    : "The latest MyAnimeList sync found this title already aligned.",
                result
            )
        }
    }

    function malSyncBadge(show, compact) {
        return _malSyncBadgeData(show, compact, false)
    }

    function malSyncStatusEntry(show) {
        var entry = show || ({})
        var badge = _malSyncBadgeData(entry, false, true)
        var result = _findMalSyncResult(entry)
        var watched = _showLocalWatchedEpisodes(entry)
        var total = Number(entry?.episodeCount || 0)
        var remoteStatus = malListStatusLabel(result?.remoteStatus)
        var remoteWatched = Number(result?.watchedEpisodes || 0)
        var localStatus = libraryListStatus(entry)
        var localProgress = watched > 0
            ? ("Local: " + watched + (total > 0 ? " / " + total : "") + " episodes")
            : (total > 0 ? ("Local: 0 / " + total + " episodes") : "Local: not started")

        return {
            id: String(entry?.id || ""),
            metadataId: _showMetadataId(entry),
            title: _showTitle(entry),
            malId: _showMalId(entry),
            badge: badge,
            badgeKey: String(badge?.key || "disabled"),
            badgeTone: String(badge?.tone || "muted"),
            localStatus: localStatus,
            localStatusLabel: malListStatusLabel(localStatus),
            localProgress: localProgress,
            remoteStatus: remoteStatus,
            remoteWatchedEpisodes: remoteWatched,
            hasSyncResult: result !== null,
            detail: String(badge?.detail || "")
        }
    }

    function _formatPlaybackError(stderrTail) {
        var text = String(stderrTail || "").trim()
        if (!text)
            return "Playback failed: no playable stream was opened for this episode."
        if ((text === "Exiting... (Errors when loading file)" || text === "errors while loading file")
                && _mpvLastMeaningfulError.length > 0)
            text = _mpvLastMeaningfulError
        if (text.indexOf("HTTP error 403") !== -1 || text.indexOf("403 Forbidden") !== -1)
            return "Playback failed: the provider rejected this stream."
        if (text.indexOf("HTTP error 404") !== -1 || text.indexOf("404 Not Found") !== -1)
            return "Playback failed: this stream is no longer available."
        if (text.indexOf("Failed to open") !== -1)
            return "Playback failed: mpv could not open the selected stream."
        if (text.indexOf("Errors when loading file") !== -1 && _mpvLastMeaningfulError.length > 0)
            text = _mpvLastMeaningfulError
        if (text.indexOf("Certificate verification failed") !== -1)
            return "Playback failed: the stream provider certificate could not be verified."
        if (text.length > 120)
            text = text.substring(0, 117) + "..."
        return "Playback failed: " + text
    }

    function _normaliseEpisodeList(episodes) {
        return (episodes || []).map(function(ep) {
            return { id: ep.id, number: ep.number }
        }).sort(function(a, b) {
            return Number(a.number) - Number(b.number)
        })
    }

    function setSetting(key, val) {
        if (key === "mode") currentMode = val
        if (key === "preferredProvider") preferredProvider = val
        if (key === "metadataProvider") metadataProviderId = val
        if (key === "streamProvider") streamProviderId = val

        if (key === "panelSize") {
            panelSize = val
            posterSize = _normalisePosterSize(val, posterSize)
        } else if (key === "posterSize") {
            posterSize = _normalisePosterSize(panelSize, val)
        }
        
        if (pluginApi) {
            pluginApi.pluginSettings[key] = val
            if (key === "panelSize" || key === "posterSize")
                pluginApi.pluginSettings.posterSize = posterSize
            pluginApi.saveSettings()
        }
    }

    function setMode(mode) {
        if (mode !== "sub" && mode !== "dub") return
        if (currentMode === mode) return

        setSetting("mode", mode)
        feedLastFetchedAt = 0

        if (currentAnime)
            fetchAnimeDetail(currentAnime)

        if (currentView === "search" && currentSearchQuery.length > 0)
            searchAnime(currentSearchQuery, true)
        else
            fetchCurrentFeed(true)
    }

    // ── Browse state ──────────────────────────────────────────────────────────
    property var    animeList:       []
    property bool   isFetchingAnime: false
    property string animeError:      ""
    property string currentView:     "top"
    property string browseFeed:      "top"
    property string currentCountry:  "ALL"
    property string currentSearchQuery: ""
    property string currentGenre:    ""
    property var    genresList:      []
    property int    browseResetToken: 0
    property int    _page:           1
    property bool   _hasMore:        true
    property real   browseScrollY:   0

    // ── Feed state ────────────────────────────────────────────────────────────
    property var    feedList:        []
    property var    feedUpcomingList: []
    property var    feedSummary:     ({ alerts: 0, upcoming: 0, following: 0 })
    property bool   isFetchingFeed:  false
    property string feedError:       ""
    property double feedLastFetchedAt: 0
    property int    feedCooldownMs:  300000
    property int    feedUnreadCount: 0
    property var    feedNotificationState: _emptyFeedNotificationState()
    property bool   _pendingStartupFeedToast: false

    // ── AniList sync state ───────────────────────────────────────────────────
    property bool   isAniListSyncBusy: false
    property string aniListSyncError: ""
    property string aniListSyncMessage: ""
    property var    aniListSyncSummary: ({})
    property var    aniListSyncResults: []
    property string _pendingAniListCommand: ""
    property bool   _pendingAniListShowsToast: true
    property bool   _suppressAniListAutoPush: false
    property bool   _pendingAniListBrowserAuth: false

    // ── MyAnimeList sync state ───────────────────────────────────────────────
    property bool   isMalSyncBusy: false
    property string malSyncError: ""
    property string malSyncMessage: ""
    property var    malSyncSummary: ({})
    property var    malSyncResults: []
    property string _pendingMalCommand: ""
    property bool   _pendingMalShowsToast: true
    property bool   _suppressMalAutoPush: false
    property bool   _pendingMalBrowserAuth: false
    property string _pendingMalBrowserAuthUrl: ""

    // ── Library view state ───────────────────────────────────────────────────
    property real libraryScrollY: 0

    // ── Detail state ──────────────────────────────────────────────────────────
    property var  currentAnime:     null
    property bool isFetchingDetail: false
    property string detailFocusEpisodeNum: ""
    property string pendingAutoPlayShowId: ""

    // ── Stream state ──────────────────────────────────────────────────────────
    property var    selectedLink:    null
    property bool   isFetchingLinks: false
    property string linksError:      ""
    property bool   isLaunchingPlayer: false
    property string playbackError:   ""
    property string currentEpisode:  ""
    property string detailError:     ""

    // ── Currently playing ─────────────────────────────────────────────────────
    property string _playingShowId: ""
    property string _playingEpNum:  ""
    property string _pendingEpisodeId: ""
    property string _pendingProgressFile: ""
    property string _activeShowId: ""
    property string _activeEpNum: ""
    property string _activeProgressFile: ""
    property string _queuedUrl: ""
    property string _queuedRef: ""
    property string _queuedTitle: ""
    property string _queuedType: ""
    property var    _queuedHeaders: ({})
    property string _queuedShowId: ""
    property string _queuedEpNum: ""
    property string _queuedProgressFile: ""
    property real _queuedStartPos: 0
    property bool _launchQueued: false
    property double _mpvLaunchStartedAt: 0
    property string _mpvStderrTail: ""
    property string _mpvLastMeaningfulError: ""

    // ── Library ───────────────────────────────────────────────────────────────
    property bool libraryLoaded: false
    property var  libraryList:   []

    // Counter that bumps whenever libraryList changes — views bind to this
    // so watched/in-library checks re-evaluate reactively
    property int libraryVersion: 0

    Component.onCompleted: {
        posterSize = _normalisePosterSize(panelSize, posterSize)
        if (pluginApi && pluginApi.pluginSettings)
            pluginApi.pluginSettings.posterSize = posterSize
        // Init crypto cache dir, eagerly load forge, persist to disk if CDN was used
        Providers.initCryptoCache((pluginApi ? pluginApi.pluginDir : "") + "/js/")
        Providers.ensureCryptoLoaded()
        _writeForgeCache()
        _migrateLibrarySchemaIfNeeded()
        _loadLibrary()
        _loadFeedNotificationState()
        _ensureProgressDir()
        fetchGenres()
        fetchPopular(true)
        if ((libraryList || []).length > 0) {
            _pendingStartupFeedToast = true
            startupFeedTimer.start()
        }
    }

    Timer {
        id: startupFeedTimer
        interval: 1500
        repeat: false
        onTriggered: root.fetchFollowingFeed(false)
    }

    Timer {
        id: aniListAutoPushTimer
        interval: 1800
        repeat: false
        onTriggered: root.pushAniListSync(false)
    }

    Timer {
        id: malAutoPushTimer
        interval: 1800
        repeat: false
        onTriggered: root.pushMalSync(false)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function _ensureProgressDir() {
        mkdirProc.command = ["mkdir", "-p", progressDir]
        mkdirProc.running = true
    }

    function _aniListSyncReady() {
        return aniListSync?.enabled === true
            && String(aniListSync?.accessToken || "").length > 0
    }

    function _malSyncReady() {
        return String(malSync?.backendSessionToken || "").length > 0
            && String(malSync?.userName || "").length > 0
    }

    function _queueAniListAutoPush() {
        if (_suppressAniListAutoPush) return
        if (!(aniListSync?.autoPush === true) || !_aniListSyncReady())
            return
        aniListAutoPushTimer.restart()
    }

    function _queueMalAutoPush() {
        if (_suppressMalAutoPush) return
        if (!(malSync?.autoPush === true) || !_malSyncReady())
            return
        malAutoPushTimer.restart()
    }

    function _normaliseLibraryEntry(entry) {
        var item = _deepClone(entry || {})
        if (!item || typeof item !== "object" || Array.isArray(item))
            item = ({})
        item.id = String(item.id || "")
        item.name = String(item.name || "")
        item.englishName = String(item.englishName || "")
        item.nativeName = String(item.nativeName || "")
        item.thumbnail = String(item.thumbnail || "")
        item.type = String(item.type || "")
        item.episodeCount = item.episodeCount || ""
        item.availableEpisodes = item.availableEpisodes || {sub: 0, dub: 0, raw: 0}
        item.season = item.season || null
        item.providerRefs = _deepClone(item.providerRefs || {})
        item.lastWatchedEpId = String(item.lastWatchedEpId || "")
        item.lastWatchedEpNum = String(item.lastWatchedEpNum || "")
        item.watchedEpisodes = Array.isArray(item.watchedEpisodes) ? item.watchedEpisodes.slice() : []
        item.episodeProgress = (item.episodeProgress && typeof item.episodeProgress === "object" && !Array.isArray(item.episodeProgress))
            ? _deepClone(item.episodeProgress)
            : ({})
        item.listStatus = libraryListStatus(item)
        item.updatedAt = Number(item.updatedAt || Date.now())
        return item
    }

    function _mergeLibraryEntry(entry, overrides) {
        var merged = _normaliseLibraryEntry(entry)
        var next = overrides || ({})
        Object.keys(next).forEach(function(key) {
            if (key === "providerRefs")
                merged.providerRefs = root._deepClone(next.providerRefs || {})
            else if (key === "watchedEpisodes")
                merged.watchedEpisodes = Array.isArray(next.watchedEpisodes) ? next.watchedEpisodes.slice() : []
            else if (key === "episodeProgress")
                merged.episodeProgress = root._deepClone(next.episodeProgress || {})
            else
                merged[key] = next[key]
        })
        if (!merged.providerRefs || typeof merged.providerRefs !== "object" || Array.isArray(merged.providerRefs))
            merged.providerRefs = ({})
        if (!Array.isArray(merged.watchedEpisodes))
            merged.watchedEpisodes = []
        if (!merged.episodeProgress || typeof merged.episodeProgress !== "object" || Array.isArray(merged.episodeProgress))
            merged.episodeProgress = ({})
        merged.listStatus = libraryListStatus(merged)
        merged.updatedAt = Number(merged.updatedAt || Date.now())
        return merged
    }

    function _mergeProgressDrivenLibraryEntry(entry, overrides, userAction) {
        var merged = _mergeLibraryEntry(entry, overrides)
        merged.listStatus = _resolvedLibraryStatus(merged, userAction || null).status
        return merged
    }

    function _saveLibrary(skipAutoSync) {
        if (!pluginApi) return
        pluginApi.pluginSettings.library = libraryList
        pluginApi.saveSettings()
        feedLastFetchedAt = 0
        libraryVersion++  // trigger reactive re-evaluation in views
        if (skipAutoSync !== true) {
            _queueAniListAutoPush()
            _queueMalAutoPush()
        }
    }

    function _loadLibrary() {
        if (!pluginApi) return
        var raw = pluginApi.pluginSettings?.library
        libraryList = (raw && Array.isArray(raw))
            ? raw.map(function(entry) { return _normaliseLibraryEntry(entry) })
            : []
        libraryLoaded = true
        feedLastFetchedAt = 0
        libraryVersion++
    }

    // ── Library API ───────────────────────────────────────────────────────────
    function isInLibrary(id) {
        var _ = libraryVersion  // reactive dependency
        return libraryList.some(function(e) { return e.id === id })
    }

    function getLibraryEntry(id) {
        var _ = libraryVersion  // reactive dependency
        return libraryList.find(function(e) { return e.id === id }) || null
    }

    function isEpisodeWatched(showId, epNum) {
        var _ = libraryVersion  // reactive dependency
        var entry = libraryList.find(function(e) { return e.id === showId })
        if (!entry) return false
        return (entry.watchedEpisodes || []).indexOf(String(epNum)) !== -1
    }

    function hasEpisodeProgress(showId, epNum) {
        var _ = libraryVersion
        var entry = libraryList.find(function(e) { return e.id === showId })
        if (!entry) return false
        return getEpisodeProgress(showId, epNum) > 0
    }

    function _progressPosition(value) {
        if (typeof value === "number")
            return value
        if (value && typeof value === "object")
            return value.position || 0
        return 0
    }

    function _progressDuration(value) {
        if (value && typeof value === "object")
            return value.duration || 0
        return 0
    }

    function _makeEntry(show, lastEpId, lastEpNum, listStatus) {
        var providerRefs = _deepClone(show?.providerRefs || {})
        var initialStatus = resolveAnimeStatus({
            currentStatus: _normaliseMalListStatus(listStatus || ""),
            watchedEpisodes: _parseEpisodeNumber(lastEpNum),
            totalEpisodes: _parseEpisodeNumber(show?.episodeCount || 0),
            userAction: lastEpNum ? "play" : null
        }).status
        if (!providerRefs.metadata)
            providerRefs.metadata = { provider: _showMetadataProviderId(show), id: _showMetadataId(show) }
        if (!providerRefs.stream && providerRefs.metadata.provider === _showStreamProviderId(show))
            providerRefs.stream = { provider: _showStreamProviderId(show), id: String(show?.id || "") }
        return _normaliseLibraryEntry({
            id: show.id, name: show.name || "",
            englishName: show.englishName || "",
            nativeName: show.nativeName || "",
            thumbnail: show.thumbnail || "",
            score: show.score || null,
            type: show.type || "",
            episodeCount: show.episodeCount || "",
            availableEpisodes: show.availableEpisodes || {sub:0,dub:0,raw:0},
            season: show.season || null,
            providerRefs: providerRefs,
            lastWatchedEpId:  lastEpId  ? String(lastEpId)  : "",
            lastWatchedEpNum: lastEpNum ? String(lastEpNum) : "",
            watchedEpisodes:  [],
            episodeProgress:  {},
            listStatus: initialStatus,
            updatedAt: Date.now()
        })
    }

    function addToLibrary(show) {
        if (isInLibrary(show.id)) return
        var updated = libraryList.slice()
        updated.push(_makeEntry(show, "", "", "plan_to_watch"))
        libraryList = updated
        _saveLibrary()
    }

    function addToLibraryWithEpisode(show, epId, epNum) {
        if (isInLibrary(show.id)) {
            updateLastWatched(show.id, epId, epNum)
            return
        }
        var updated = libraryList.slice()
        updated.push(_makeEntry(show, epId, epNum, "watching"))
        libraryList = updated
        _saveLibrary()
    }

    function removeFromLibrary(id) {
        libraryList = libraryList.filter(function(e) { return e.id !== id })
        _saveLibrary()
    }

    function updateLastWatched(showId, epId, epNum) {
        var updated = libraryList.map(function(e) {
            if (e.id !== showId) return e
            return _mergeProgressDrivenLibraryEntry(e, {
                lastWatchedEpId:  String(epId),
                lastWatchedEpNum: String(epNum),
                updatedAt: Date.now()
            }, "play")
        })
        libraryList = updated
        _saveLibrary()
    }

    function markEpisodeWatched(showId, epNum) {
        var updated = libraryList.map(function(e) {
            if (e.id !== showId) return e
            var watched = (e.watchedEpisodes || []).slice()
            if (watched.indexOf(String(epNum)) === -1) watched.push(String(epNum))
            // Clear progress since it's fully watched
            var prog = Object.assign({}, e.episodeProgress || {})
            delete prog[String(epNum)]
            return _mergeProgressDrivenLibraryEntry(e, {
                watchedEpisodes:  watched,
                episodeProgress:  prog,
                updatedAt: Date.now()
            }, "play")
        })
        libraryList = updated
        _saveLibrary()
    }

    function unmarkEpisodeWatched(showId, epNum) {
        var updated = libraryList.map(function(e) {
            if (e.id !== showId) return e
            var watched = (e.watchedEpisodes || []).filter(function(item) {
                return item !== String(epNum)
            })
            return _mergeProgressDrivenLibraryEntry(e, {
                lastWatchedEpId: e.lastWatchedEpNum === String(epNum) ? "" : e.lastWatchedEpId,
                lastWatchedEpNum: e.lastWatchedEpNum === String(epNum) ? "" : e.lastWatchedEpNum,
                watchedEpisodes: watched,
                episodeProgress: e.episodeProgress || {},
                updatedAt: Date.now()
            })
        })
        libraryList = updated
        _saveLibrary()
    }

    function toggleEpisodeWatched(show, epId, epNum) {
        if (!show || !show.id) return
        if (!isInLibrary(show.id)) {
            addToLibraryWithEpisode(show, epId, epNum)
            markEpisodeWatched(show.id, epNum)
            return
        }
        if (isEpisodeWatched(show.id, epNum))
            unmarkEpisodeWatched(show.id, epNum)
        else {
            updateLastWatched(show.id, epId, epNum)
            markEpisodeWatched(show.id, epNum)
        }
    }

    function markEpisodesThrough(show, epId, epNum, episodeIndex) {
        if (!show || !show.id) return

        var episodes = show.episodes || []
        var endIndex = Number(episodeIndex)
        if (!(endIndex >= 0)) {
            endIndex = episodes.findIndex(function(ep) {
                return String(ep.number) === String(epNum)
            })
        }
        if (endIndex < 0) return

        var watchedMap = {}
        for (var i = 0; i <= endIndex && i < episodes.length; i++)
            watchedMap[String(episodes[i].number)] = true

        var updated = libraryList.slice()
        var existingIndex = updated.findIndex(function(entry) { return entry.id === show.id })
        if (existingIndex === -1) {
            updated.push(_makeEntry(show, epId, epNum, "watching"))
            existingIndex = updated.length - 1
        }

        var current = updated[existingIndex]
        var mergedWatched = []
        var seen = {}

        episodes.forEach(function(ep) {
            var number = String(ep.number)
            if (watchedMap[number] || (current.watchedEpisodes || []).indexOf(number) !== -1) {
                mergedWatched.push(number)
                seen[number] = true
            }
        })

        ;(current.watchedEpisodes || []).forEach(function(number) {
            number = String(number)
            if (seen[number]) return
            mergedWatched.push(number)
            seen[number] = true
        })

        var prog = Object.assign({}, current.episodeProgress || {})
        Object.keys(watchedMap).forEach(function(number) {
            delete prog[number]
        })

        updated[existingIndex] = _mergeProgressDrivenLibraryEntry(current, {
            lastWatchedEpId: String(epId || ""),
            lastWatchedEpNum: String(epNum || ""),
            watchedEpisodes: mergedWatched,
            episodeProgress: prog,
            updatedAt: Date.now()
        }, "play")

        libraryList = updated
        _saveLibrary()
    }

    function _parseEpisodeNumber(value) {
        var parsed = Number(value)
        return isFinite(parsed) ? parsed : 0
    }

    function _showWatchTarget(show) {
        var episodes = _normaliseEpisodeList(show?.episodes || [])
        if (episodes.length === 0)
            return null

        var targetIndex = episodes.length - 1
        var targetEpisode = episodes[targetIndex]
        if (!targetEpisode || String(targetEpisode.number || "").length === 0)
            return null

        return {
            index: targetIndex,
            episodeId: String(targetEpisode.id || ""),
            episodeNumber: String(targetEpisode.number || ""),
            loadedEpisodes: episodes.length
        }
    }

    function _isCompletedShowStatus(show) {
        var status = String(show?.status || "").toUpperCase()
        return status === "FINISHED" || status === "CANCELLED"
    }

    function getShowWatchAction(show) {
        var _ = libraryVersion  // reactive dependency
        if (!show || !show.id)
            return null

        var target = _showWatchTarget(show)
        if (!target)
            return null

        var totalEpisodes = _parseEpisodeNumber(show?.episodeCount)
        var availableMap = show?.availableEpisodes || {}
        var availableEpisodes = _parseEpisodeNumber(availableMap[currentMode] || 0)
        if (availableEpisodes <= 0)
            availableEpisodes = _parseEpisodeNumber(show?.availableEpisodes?.sub || show?.availableEpisodes?.raw || 0)
        availableEpisodes = Math.max(availableEpisodes, target.loadedEpisodes)

        var canMarkFullyWatched = _isCompletedShowStatus(show) &&
            (totalEpisodes <= 0 || availableEpisodes >= totalEpisodes)

        var label = canMarkFullyWatched ? "Mark Watched" : "Mark Up to Date"
        var doneLabel = canMarkFullyWatched ? "Fully Watched" : "Up to Date"

        var entry = getLibraryEntry(show.id)
        var alreadyApplied = false
        if (entry && String(entry.lastWatchedEpNum || "") === target.episodeNumber) {
            alreadyApplied = true
            var episodes = _normaliseEpisodeList(show?.episodes || [])
            for (var i = 0; i <= target.index && i < episodes.length; i++) {
                if (!isEpisodeWatched(show.id, episodes[i].number)) {
                    alreadyApplied = false
                    break
                }
            }
        }

        return {
            label: alreadyApplied ? doneLabel : label,
            targetEpisodeId: target.episodeId,
            targetEpisodeNumber: target.episodeNumber,
            targetEpisodeIndex: target.index,
            isComplete: alreadyApplied,
            marksFullyWatched: canMarkFullyWatched
        }
    }

    function applyShowWatchAction(show) {
        var action = getShowWatchAction(show)
        if (!action || action.isComplete)
            return false

        markEpisodesThrough(
            show,
            action.targetEpisodeId,
            action.targetEpisodeNumber,
            action.targetEpisodeIndex
        )
        fetchFollowingFeed(true)
        return true
    }

    function saveEpisodeProgress(showId, epNum, position, duration) {
        var updated = libraryList.map(function(e) {
            if (e.id !== showId) return e
            var prog = Object.assign({}, e.episodeProgress || {})
            prog[String(epNum)] = {
                position: position,
                duration: duration || 0
            }
            return _mergeProgressDrivenLibraryEntry(e, {
                episodeProgress:  prog,
                updatedAt: Date.now()
            }, "play")
        })
        libraryList = updated
        _saveLibrary()
    }

    function getEpisodeProgress(showId, epNum) {
        var entry = libraryList.find(function(e) { return e.id === showId })
        if (!entry) return 0
        return _progressPosition((entry.episodeProgress || {})[String(epNum)])
    }

    function getEpisodeProgressRatio(showId, epNum) {
        var entry = libraryList.find(function(e) { return e.id === showId })
        if (!entry) return 0
        var progress = (entry.episodeProgress || {})[String(epNum)]
        var position = _progressPosition(progress)
        var duration = _progressDuration(progress)
        if (duration <= 0 || position <= 0) return 0
        return Math.max(0, Math.min(1, position / duration))
    }

    function getContinueWatchingList() {
        var _ = libraryVersion
        return libraryList
            .filter(function(entry) {
                var prog = entry.episodeProgress || {}
                return Object.keys(prog).some(function(key) {
                    return root._progressPosition(prog[key]) > 0
                })
            })
            .sort(function(a, b) {
                return (b.updatedAt || 0) - (a.updatedAt || 0)
            })
    }

    function getNextUnwatchedEpisode(show) {
        if (!show || !show.id) return null
        var episodes = show.episodes || []
        if (episodes.length === 0) return null

        var entry = getLibraryEntry(show.id)
        var lastWatchedNum = entry?.lastWatchedEpNum || ""

        if (lastWatchedNum) {
            var currentIndex = episodes.findIndex(function(ep) {
                return String(ep.number) === String(lastWatchedNum)
            })

            if (currentIndex >= 0) {
                var currentEpisode = episodes[currentIndex]
                if (!isEpisodeWatched(show.id, currentEpisode.number) ||
                    hasEpisodeProgress(show.id, currentEpisode.number))
                    return currentEpisode

                for (var i = currentIndex + 1; i < episodes.length; i++) {
                    if (!isEpisodeWatched(show.id, episodes[i].number))
                        return episodes[i]
                }
            }
        }

        for (var j = 0; j < episodes.length; j++) {
            if (!isEpisodeWatched(show.id, episodes[j].number) ||
                hasEpisodeProgress(show.id, episodes[j].number))
                return episodes[j]
        }

        return episodes[episodes.length - 1] || null
    }

    function playNextUnwatched(show) {
        var nextEpisode = getNextUnwatchedEpisode(show)
        if (!show || !nextEpisode) return
        fetchStreamLinks(show.id, nextEpisode.id, nextEpisode.number)
    }

    function commitPendingEpisodeSelection() {
        if (!currentAnime || !_playingShowId || !_playingEpNum) return
        if (isInLibrary(_playingShowId))
            updateLastWatched(_playingShowId, _pendingEpisodeId, _playingEpNum)
        else
            addToLibraryWithEpisode(currentAnime, _pendingEpisodeId, _playingEpNum)
    }

    function setBrowseScroll(y) {
        browseScrollY = Math.max(0, y || 0)
    }

    function setLibraryScroll(y) {
        libraryScrollY = Math.max(0, y || 0)
    }

    // ── MPV launch & progress tracking ───────────────────────────────────────
    property string _pendingUrl:   ""
    property string _pendingRef:   ""
    property string _pendingTitle: ""
    property string _pendingType:  ""
    property var    _pendingHeaders: ({})

    // Step 1: called from DetailView Connections
    function playWithMpv(url, referer, title, headers, mediaType) {
        if (!url || url.length === 0) return
        playbackError = ""
        isLaunchingPlayer = true
        _pendingUrl   = url
        _pendingRef   = referer
        _pendingTitle = title
        _pendingType  = mediaType || ""
        _pendingHeaders = headers || ({})
        _pendingProgressFile = progressDir + "/" + _playingShowId + "-ep" + _playingEpNum + ".txt"

        // Read existing progress file if it exists (for resume)
        preReadProc.command = [
            "sh", "-c",
            "test -f \"$1\" && cat \"$1\" || printf 'position=0\n'",
            "sh",
            _pendingProgressFile
        ]
        preReadProc._buf = ""
        if (preReadProc.running) preReadProc.running = false
        Qt.callLater(function() { preReadProc.running = true })
    }

    Process {
        id: preReadProc
        property string _buf: ""

        onRunningChanged: {
            if (running) return
            var startPos = 0
            var lines = _buf.split("\n")
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim()
                if (line.startsWith("position=")) {
                    startPos = parseFloat(line.substring(9)) || 0
                }
            }
            _buf = ""
            _doLaunchMpv(startPos)
        }

        stdout: SplitParser {
            onRead: function(data) { preReadProc._buf += data + "\n" }  // SplitParser strips newlines
        }
    }

    function _startMpvSession(showId, epNum, progressFile, startPos, url, referer, title, headers, mediaType) {
        _activeShowId = showId
        _activeEpNum = epNum
        _activeProgressFile = progressFile
        _mpvLaunchStartedAt = Date.now()
        _mpvStderrTail = ""
        _mpvLastMeaningfulError = ""
        var args = [
            "mpv", "--fs", "--force-window=yes",
            "--title=" + (title || "AnimeReloaded"),
            "--script=" + luaPath,
            "--script-opts=progress_file=" + progressFile,
        ]
        if (startPos > 5)
            args.push("--start=" + Math.floor(startPos))
        var effectiveHeaders = headers || ({})
        var effectiveReferer = referer || effectiveHeaders["Referer"] || effectiveHeaders["Referrer"] || ""
        if (effectiveReferer && effectiveReferer.length > 0) {
            args.push("--referrer=" + effectiveReferer)
            effectiveHeaders["Referer"] = effectiveReferer
        }
        if (effectiveHeaders["User-Agent"] && effectiveHeaders["User-Agent"].length > 0)
            args.push("--user-agent=" + effectiveHeaders["User-Agent"])
        var extraHeaders = []
        Object.keys(effectiveHeaders).forEach(function(key) {
            if (key === "User-Agent" || key === "Referrer")
                return
            var value = String(effectiveHeaders[key] || "")
            if (value.length > 0)
                extraHeaders.push(key + ": " + value)
        })
        if (extraHeaders.length > 0)
            args.push("--http-header-fields=" + extraHeaders.join(","))
        if (mediaType === "hls") {
            args.push("--demuxer-lavf-o=protocol_whitelist=file,http,https,tcp,tls,crypto,data")
            args.push("--load-unsafe-playlists=yes")
        }
        args.push(url)

        mpvProcess.command = args
        mpvProcess.running = true
    }

    function _doLaunchMpv(startPos) {
        var showId = _playingShowId
        var epNum = _playingEpNum
        var progressFile = _pendingProgressFile
        var url = _pendingUrl
        var referer = _pendingRef
        var title = _pendingTitle
        var mediaType = _pendingType
        var headers = _pendingHeaders

        if (mpvProcess.running) {
            _queuedShowId = showId
            _queuedEpNum = epNum
            _queuedProgressFile = progressFile
            _queuedUrl = url
            _queuedRef = referer
            _queuedTitle = title
            _queuedType = mediaType
            _queuedHeaders = headers
            _queuedStartPos = startPos
            _launchQueued = true
            mpvProcess.running = false
            return
        }

        _startMpvSession(showId, epNum, progressFile, startPos, url, referer, title, headers, mediaType)
    }

    Process {
        id: mpvProcess

        onRunningChanged: {
            if (running) {
                root.isLaunchingPlayer = false
                return
            }
            root.isLaunchingPlayer = false
            if (!root._activeProgressFile) return
            // mpv exited — read the progress file
            postReadProc.command = [
                "sh", "-c",
                "test -f \"$1\" && cat \"$1\" || printf 'duration=0\nposition=0\n'",
                "sh",
                root._activeProgressFile
            ]
            postReadProc._buf    = ""
            postReadProc._showId = root._activeShowId
            postReadProc._epNum  = root._activeEpNum
            postReadProc._pfile  = root._activeProgressFile
            postReadProc._stderrTail = root._mpvStderrTail
            postReadProc._launchStartedAt = root._mpvLaunchStartedAt
            if (postReadProc.running) postReadProc.running = false
            Qt.callLater(function() { postReadProc.running = true })
        }

        stderr: SplitParser {
            onRead: function(data) {
                var line = (data || "").trim()
                if (line.length === 0) return
                root._mpvStderrTail = line
                if (line.indexOf("Exiting...") === -1 && line.indexOf("errors while loading file") === -1)
                    root._mpvLastMeaningfulError = line
                Logger.w("AnimeReloaded", "mpv:", line)
            }
        }
        stdout: SplitParser {
            onRead: function(data) {
                var line = (data || "").trim()
                if (line.length === 0) return
                root._mpvStderrTail = line
                if (line.indexOf("Exiting...") === -1 && line.indexOf("errors while loading file") === -1)
                    root._mpvLastMeaningfulError = line
                Logger.w("AnimeReloaded", "mpv:", line)
            }
        }
    }

    Process {
        id: postReadProc
        property string _buf:    ""
        property string _showId: ""
        property string _epNum:  ""
        property string _pfile:  ""
        property string _stderrTail: ""
        property double _launchStartedAt: 0

        onRunningChanged: {
            if (running) return
            var dur = 0, pos = 0
            var lines = _buf.split("\n")
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim()
                if (line.startsWith("duration=")) dur = parseFloat(line.substring(9)) || 0
                if (line.startsWith("position=")) pos = parseFloat(line.substring(9)) || 0
            }
            _buf = ""
            var ranBriefly = _launchStartedAt > 0 && (Date.now() - _launchStartedAt) < 2500

            if (dur > 0 && pos > 0) {
                if (pos / dur >= 0.85) {
                    // Fully watched
                    root.markEpisodeWatched(_showId, _epNum)
                    // Delete the progress file
                    rmProc.command = ["rm", "-f", _pfile]
                    rmProc.running = true
                } else {
                    // Partially watched — save position
                    root.saveEpisodeProgress(_showId, _epNum, pos, dur)
                }
            } else if (ranBriefly) {
                root.playbackError = root._formatPlaybackError(_stderrTail)
            }

            root._activeShowId = ""
            root._activeEpNum = ""
            root._activeProgressFile = ""
            root._mpvLaunchStartedAt = 0
            root._mpvStderrTail = ""
            root._mpvLastMeaningfulError = ""
            _stderrTail = ""
            _launchStartedAt = 0

            if (root._launchQueued) {
                var nextShowId = root._queuedShowId
                var nextEpNum = root._queuedEpNum
                var nextProgressFile = root._queuedProgressFile
                var nextStartPos = root._queuedStartPos
                var nextUrl = root._queuedUrl
                var nextRef = root._queuedRef
                var nextTitle = root._queuedTitle
                var nextType = root._queuedType
                var nextHeaders = root._queuedHeaders

                root._launchQueued = false
                root._queuedShowId = ""
                root._queuedEpNum = ""
                root._queuedProgressFile = ""
                root._queuedStartPos = 0
                root._queuedUrl = ""
                root._queuedRef = ""
                root._queuedTitle = ""
                root._queuedType = ""
                root._queuedHeaders = ({})

                root._startMpvSession(
                    nextShowId,
                    nextEpNum,
                    nextProgressFile,
                    nextStartPos,
                    nextUrl,
                    nextRef,
                    nextTitle,
                    nextHeaders,
                    nextType
                )
            }
        }

        stdout: SplitParser {
            onRead: function(data) { postReadProc._buf += data + "\n" }
        }
    }

    // ── Utility processes ────────────────────────────────────────────────────
    Process { id: mkdirProc }
    Process { id: rmProc }

    // Writes forge cache to disk after CDN download
    Process {
        id: forgeCacheWriteProc
        onRunningChanged: {
            if (!running) {
                Providers.markForgeCacheWritten()
                console.log("[Crypto] Forge cache written to disk")
            }
        }
    }

    function _writeForgeCache() {
        if (!Providers.hasPendingForgeCache()) return
        var cachePath = (pluginApi ? pluginApi.pluginDir : "") + "/js/forge.cache.js"
        var cdnUrl = Providers.getForgeCdnUrl()
        // Download directly via curl — keeps command tiny, no content in Process args
        forgeCacheWriteProc.command = ["curl", "-sL", "-o", cachePath, cdnUrl]
        forgeCacheWriteProc.running = true
    }

    // ── AniList sync result handler ──────────────────────────────────────────
    function _handleAniListSyncResult(command, d) {
        if (d.config)
            root.updateAniListSyncConfig(d.config)
        root.aniListSyncSummary = d.summary || ({})
        root.aniListSyncResults = Array.isArray(d.results) ? d.results : []
        if ((command === "pull" || command === "push") && Array.isArray(d.library)) {
            root._suppressAniListAutoPush = true
            root.libraryList = d.library.map(function(entry) {
                return root._normaliseLibraryEntry(entry)
            })
            root._saveLibrary(true)
            root._suppressAniListAutoPush = false
            if (command === "pull")
                root.fetchFollowingFeed(true)
        }

        var summary = d.summary || ({})
        if (command === "auth-url" && d.authUrl) {
            root.aniListSyncMessage = "Opened AniList authorization in the browser. Paste the returned callback URL or access token to finish."
            Qt.openUrlExternally(d.authUrl)
        } else if (command === "connect-token") {
            root._pendingAniListBrowserAuth = false
            root.aniListAuthDraft = ""
            root.aniListSyncMessage = "Connected to AniList as " + String(((d || {}).user || {}).name || root.aniListSync.userName || "your account") + "."
        } else if (command === "refresh") {
            root.aniListSyncMessage = "Refreshed AniList session."
        } else if (command === "delete-entry") {
            var removedTitle = String((d && d.results && d.results.length > 0 ? d.results[0].title : "") || "")
            root.aniListSyncMessage = removedTitle.length > 0
                ? ("Removed " + removedTitle + " from AniList.")
                : root._formatAniListSyncMessage("delete", summary)
        } else if (command === "push") {
            root.aniListSyncMessage = root._formatAniListSyncMessage("push", summary)
        } else if (command === "pull") {
            root.aniListSyncMessage = root._formatAniListSyncMessage("pull", summary)
        } else {
            root.aniListSyncMessage = root._formatAniListSyncMessage("", summary)
        }
        root.aniListSyncError = ""

        _showSyncFeedback("AniList", command, root.aniListSyncMessage, summary, root.aniListSyncResults, root._pendingAniListShowsToast, false)
        root._pendingAniListCommand = ""
    }

    function _queueAniListCommandJS(command, includeLibrary, extraArgs, showToast) {
        _pendingAniListCommand = String(command || "")
        _pendingAniListShowsToast = showToast !== false
        aniListSyncError = ""
        aniListSyncMessage = ""

        var config = _normaliseAniListSync(aniListSync)
        var aniListArgs = { config: config }

        if (includeLibrary)
            aniListArgs.libraryEntries = libraryList || []
        if (command === "connect-token")
            aniListArgs.authResult = (extraArgs || [])[0] || ""
        if (command === "delete-entry") {
            aniListArgs.mediaId = (extraArgs || [])[0] || ""
            aniListArgs.title = (extraArgs || [])[1] || ""
        }

        isAniListSyncBusy = true

        Providers.sync("anilist", command, aniListArgs, function(err, d) {
            isAniListSyncBusy = false
            if (err) {
                root.aniListSyncError = String(err)
                root.aniListSyncMessage = ""
                _showSyncFeedback("AniList", command, root.aniListSyncError, {}, [], root._pendingAniListShowsToast, true)
                root._pendingAniListCommand = ""
                if (command === "auth-url")
                    root._pendingAniListBrowserAuth = false
                return
            }
            if (!d) {
                root.aniListSyncError = "AniList command did not return any data."
                root.aniListSyncMessage = ""
                _showSyncFeedback("AniList", command, root.aniListSyncError, {}, [], root._pendingAniListShowsToast, true)
                root._pendingAniListCommand = ""
                return
            }
            _handleAniListSyncResult(command, d)
        })
    }

    // ── MAL sync result handler ──────────────────────────────────────────────
    function _handleMalSyncResult(command, d) {
        if (d.config)
            root.updateMalSyncConfig(d.config)
        root.malSyncSummary = d.summary || ({})
        root.malSyncResults = Array.isArray(d.results) ? d.results : []
        if ((command === "pull" || command === "push") && Array.isArray(d.library)) {
            root._suppressMalAutoPush = true
            root.libraryList = d.library.map(function(entry) {
                return root._normaliseLibraryEntry(entry)
            })
            root._saveLibrary(true)
            root._suppressMalAutoPush = false
            if (command === "pull")
                root.fetchFollowingFeed(true)
        }

        var summary = d.summary || ({})
        if (command === "auth-url" && d.authUrl) {
            if (root._pendingMalBrowserAuth) {
                root.malSyncMessage = "Waiting for MyAnimeList authorization in the browser."
                root._startMalBrowserListenerJS(d.authUrl)
            } else {
                root.malSyncMessage = "Opened MyAnimeList authorization in the browser."
                Qt.openUrlExternally(d.authUrl)
            }
        } else if (command === "refresh") {
            root.malSyncMessage = "Refreshed MyAnimeList session."
        } else if (command === "delete-entry") {
            var removedTitle = String((d && d.results && d.results.length > 0 ? d.results[0].title : "") || "")
            root.malSyncMessage = removedTitle.length > 0
                ? ("Removed " + removedTitle + " from MyAnimeList.")
                : root._formatMalSyncMessage("delete", summary)
        } else if (command === "push") {
            root.malSyncMessage = root._formatMalSyncMessage("push", summary)
        } else if (command === "pull") {
            root.malSyncMessage = root._formatMalSyncMessage("pull", summary)
        } else {
            root.malSyncMessage = root._formatMalSyncMessage("", summary)
        }
        root.malSyncError = ""

        _showSyncFeedback("MyAnimeList", command, root.malSyncMessage, summary, root.malSyncResults, root._pendingMalShowsToast, false)
        root._pendingMalCommand = ""
    }

    function _queueMalCommandJS(command, includeLibrary, extraArgs, showToast) {
        _pendingMalCommand = String(command || "")
        _pendingMalShowsToast = showToast !== false
        malSyncError = ""
        malSyncMessage = ""

        var config = _normaliseMalSync(malSync)
        var malArgs = { config: config }

        if (includeLibrary)
            malArgs.libraryEntries = libraryList || []
        if (command === "delete-entry") {
            malArgs.malId = (extraArgs || [])[0] || ""
            malArgs.title = (extraArgs || [])[1] || ""
        }
        if (command === "listen-exchange")
            malArgs.timeout = 240

        isMalSyncBusy = true

        Providers.sync("myanimelist", command, malArgs, function(err, d) {
            isMalSyncBusy = false
            if (err) {
                root.malSyncError = String(err)
                root.malSyncMessage = ""
                _showSyncFeedback("MyAnimeList", command, root.malSyncError, {}, [], root._pendingMalShowsToast, true)
                root._pendingMalCommand = ""
                root._pendingMalBrowserAuth = false
                root._pendingMalBrowserAuthUrl = ""
                return
            }
            if (!d) {
                root.malSyncError = "MyAnimeList command did not return any data."
                root.malSyncMessage = ""
                _showSyncFeedback("MyAnimeList", command, root.malSyncError, {}, [], root._pendingMalShowsToast, true)
                root._pendingMalCommand = ""
                return
            }
            _handleMalSyncResult(command, d)
        })
    }

    function _startMalBrowserListenerJS(authUrl) {
        root._pendingMalBrowserAuthUrl = String(authUrl || "")
        var config = _normaliseMalSync(malSync)

        isMalSyncBusy = true
        malSyncError = ""
        malSyncMessage = "Waiting for MyAnimeList authorization in the browser."

        Providers.sync("myanimelist", "listen-exchange", {
            config: config,
            timeout: 240
        }, function(err, d) {
            isMalSyncBusy = false
            root._pendingMalBrowserAuth = false
            root._pendingMalBrowserAuthUrl = ""
            if (err) {
                root.malSyncError = String(err)
                root.malSyncMessage = ""
                return
            }
            if (d.config) root.updateMalSyncConfig(d.config)
            root.malSyncMessage = "Connected to MyAnimeList as " + String(((d || {}).user || {}).name || root.malSync.userName || "your account") + "."
            root.malSyncError = ""
            _showSyncFeedback("MyAnimeList", "connect-token", root.malSyncMessage, {}, [], true, false)
        })

        Qt.callLater(function() { Qt.openUrlExternally(authUrl) })
    }

    // ── Browse / metadata helpers ──────────────────────────────────────────────

    function _runBrowseJS(providerId, command, args, reset) {
        var cacheKey = [providerId, command, JSON.stringify(args)].join("\u241f")
        if (browseCache[cacheKey]) {
            var cached = _deepClone(browseCache[cacheKey])
            animeError = ""
            isFetchingAnime = false
            if (reset)
                browseResetToken++
            animeList = reset ? (cached.results || []) : animeList.concat(cached.results || [])
            _hasMore = cached.hasNextPage || false
            _page++
            return
        }
        isFetchingAnime = true
        animeError = ""
        Providers.metadata(providerId, command, args, function(err, d) {
            isFetchingAnime = false
            if (err) { animeError = err; return }
            if (!d) return
            browseCache[cacheKey] = _deepClone({ results: d.results || [], hasNextPage: d.hasNextPage || false })
            var results = d.results || []
            if (reset)
                browseResetToken++
            animeList = reset ? results : animeList.concat(results)
            _hasMore = d.hasNextPage || false
            _page++
        })
    }

    // ── Public API ────────────────────────────────────────────────────────────
    function startAniListBrowserAuth() {
        if (String(aniListSync?.clientId || "").trim().length === 0) {
            aniListSyncError = "Enter your AniList client id before starting browser login."
            return
        }
        _pendingAniListBrowserAuth = true
        aniListSyncError = ""
        aniListSyncMessage = "Opening AniList sign-in..."
        _queueAniListCommandJS("auth-url", false, [], false)
    }

    function completeAniListBrowserAuth(authResult, showToast) {
        if (String(authResult || "").trim().length === 0) {
            aniListSyncError = "Paste the AniList callback URL or access token first."
            return
        }
        aniListSyncError = ""
        aniListSyncMessage = "Finishing AniList sign-in..."
        _queueAniListCommandJS("connect-token", false, [authResult], showToast !== false)
    }

    function refreshAniListSyncSession(showToast) {
        if (!_aniListSyncReady()) {
            aniListSyncError = "Connect an AniList account before refreshing."
            return
        }
        _queueAniListCommandJS("refresh", false, [], showToast !== false)
    }

    function pushAniListSync(showToast) {
        if ((libraryList || []).length === 0) {
            aniListSyncError = "Your library is empty."
            return
        }
        if (!_aniListSyncReady()) {
            aniListSyncError = "Connect AniList before pushing library progress."
            return
        }
        _queueAniListCommandJS("push", true, [], showToast !== false)
    }

    function pullAniListSync(showToast) {
        if (!_aniListSyncReady()) {
            aniListSyncError = "Connect AniList before pulling progress."
            return
        }
        _queueAniListCommandJS("pull", true, [], showToast !== false)
    }

    function removeShowFromAniList(show, showToast) {
        if (!_aniListSyncReady()) {
            aniListSyncError = "Connect AniList before removing titles from your AniList list."
            return
        }
        var mediaId = _showAniListMediaId(show)
        if (mediaId.length === 0) {
            aniListSyncError = "No AniList media id is available for this title."
            return
        }
        var title = String(show?.englishName || show?.name || "")
        _queueAniListCommandJS("delete-entry", false, [mediaId, title], showToast !== false)
    }

    function startMalBrowserAuth() {
        if (String(malSync?.backendUrl || "").trim().length === 0) {
            malSyncError = "The MyAnimeList backend URL is not configured."
            return
        }
        _pendingMalBrowserAuth = true
        malSyncError = ""
        malSyncMessage = "Preparing MyAnimeList sign-in..."
        _queueMalCommandJS("auth-url", false, [], false)
    }

    function refreshMalSyncSession(showToast) {
        if (String(malSync?.backendSessionToken || "").length === 0) {
            malSyncError = "Connect a MyAnimeList account before refreshing."
            return
        }
        _queueMalCommandJS("refresh", false, [], showToast !== false)
    }

    function pushMalSync(showToast) {
        if ((libraryList || []).length === 0) {
            malSyncError = "Your library is empty."
            return
        }
        if (!_malSyncReady()) {
            malSyncError = "Connect MyAnimeList before pushing library progress."
            return
        }
        _queueMalCommandJS("push", true, [], showToast !== false)
    }

    function pullMalSync(showToast) {
        if (!_malSyncReady()) {
            malSyncError = "Connect MyAnimeList before pulling progress."
            return
        }
        _queueMalCommandJS("pull", true, [], showToast !== false)
    }

    function removeShowFromMal(show, showToast) {
        if (!_malSyncReady()) {
            malSyncError = "Connect MyAnimeList before removing titles from your MAL list."
            return
        }
        var malId = _showMalId(show)
        if (malId.length === 0) {
            malSyncError = "No MyAnimeList mapping is available for this title."
            return
        }
        var title = String(show?.englishName || show?.name || "")
        _queueMalCommandJS("delete-entry", false, [malId, title], showToast !== false)
    }

    function fetchGenres() {
        if (genresList.length > 0) return
        Providers.metadata(metadataProviderId, "genres", {}, function(err, data) {
            if (err) { Logger.w("AnimeReloaded", "genres error:", err); return }
            root.genresList = root._filterVisibleGenres(data || [])
            if (!root._isVisibleGenre(root.currentGenre))
                root.currentGenre = ""
        })
    }

    function _runFeedCommand(forceRefresh) {
        isFetchingFeed = true
        feedError = ""
        if (forceRefresh === true) feedLastFetchedAt = 0
        Providers.metadata(metadataProviderId, "feed", {
            libraryEntries: libraryList || [],
            mode: currentMode,
            streamProvider: streamProviderId
        }, function(err, d) {
            isFetchingFeed = false
            if (err) { feedError = err; return }
            if (!d) return
            _applyFeedPayload(d)
        })
    }

    function fetchFollowingFeed(forceRefresh) {
        if (!libraryLoaded) return
        if ((libraryList || []).length === 0) {
            feedList = []
            feedUpcomingList = []
            feedSummary = ({ alerts: 0, upcoming: 0, following: 0 })
            feedError = ""
            feedLastFetchedAt = Date.now()
            feedUnreadCount = 0
            return
        }
        var now = Date.now()
        if (!forceRefresh && feedList.length > 0 && (now - feedLastFetchedAt) < feedCooldownMs)
            return
        _runFeedCommand(forceRefresh)
    }

    function markFeedNotificationsSeen() {
        if ((feedList || []).length === 0)
            return
        var state = _normaliseFeedNotificationState(feedNotificationState)
        var changed = false
        for (var i = 0; i < feedList.length; i++) {
            var item = feedList[i]
            var mediaId = _feedMediaId(item)
            var latestEpisode = _feedReleasedEpisode(item)
            if (!mediaId || latestEpisode <= 0)
                continue
            var entry = _feedStateEntry(state, mediaId, true)
            if (latestEpisode > Number(entry.lastSeenEpisode || 0)) {
                entry.lastSeenEpisode = latestEpisode
                changed = true
            }
        }
        feedNotificationState = state
        _recomputeFeedUnreadCount(feedList, feedNotificationState)
        if (changed)
            _saveFeedNotificationState()
    }

    function setGenre(genre) {
        if (currentGenre === genre) return
        currentGenre = genre
        if (currentView === "search" && currentSearchQuery.length > 0)
            searchAnime(currentSearchQuery, true)
        else
            fetchCurrentFeed(true)
    }

    function fetchCurrentFeed(reset) {
        if (browseFeed === "recent")
            fetchRecent(reset)
        else
            fetchPopular(reset)
    }

    function fetchPopular(reset) {
        if (reset) { _page = 1; _hasMore = true }
        if (!_hasMore || isFetchingAnime) return
        browseFeed = "top"
        currentView = "top"
        currentSearchQuery = ""
        _runBrowseJS(metadataProviderId, "popular", {
            page: _page,
            mode: currentMode,
            genre: currentGenre || null,
            streamProvider: streamProviderId
        }, reset || _page === 1)
    }

    function fetchRecent(reset) {
        if (reset) { _page = 1; _hasMore = true }
        if (!_hasMore || isFetchingAnime) return
        browseFeed = "recent"
        currentView = "recent"
        currentSearchQuery = ""
        _runBrowseJS(metadataProviderId, "recent", {
            page: _page,
            mode: currentMode,
            country: currentCountry,
            streamProvider: streamProviderId
        }, reset || _page === 1)
    }

    function fetchNextPage() {
        if (currentView === "search")
            searchAnime(currentSearchQuery, false)
        else if (browseFeed === "recent")
            fetchRecent(false)
        else
            fetchPopular(false)
    }

    function searchAnime(query, reset) {
        if (reset) { _page = 1; _hasMore = true }
        if (isFetchingAnime) return
        currentView = "search"
        currentSearchQuery = query
        _runBrowseJS(metadataProviderId, "search", {
            query: query,
            mode: currentMode,
            page: _page,
            genre: currentGenre || null,
            streamProvider: streamProviderId
        }, reset || _page === 1)
    }

    function fetchAnimeDetail(show) {
        pendingAutoPlayShowId = ""
        detailFocusEpisodeNum = ""
        _fetchAnimeDetail(show)
    }

    function openAnimeDetail(show, focusEpisodeNum) {
        pendingAutoPlayShowId = ""
        detailFocusEpisodeNum = focusEpisodeNum ? String(focusEpisodeNum) : ""
        _fetchAnimeDetail(show)
    }

    function playNextForShow(show, focusEpisodeNum) {
        if (!show || !show.id) return
        pendingAutoPlayShowId = String(show.id)
        detailFocusEpisodeNum = focusEpisodeNum ? String(focusEpisodeNum) : ""
        _fetchAnimeDetail(show)
    }

    function _maybeAutoPlayPendingShow(show) {
        if (!show || !show.id) return
        if (String(show.id) !== String(pendingAutoPlayShowId || ""))
            return
        pendingAutoPlayShowId = ""
        Qt.callLater(function() {
            if (!currentAnime || String(currentAnime.id) !== String(show.id))
                return
            playNextUnwatched(currentAnime)
        })
    }

    function _fetchAnimeDetail(show) {
        currentAnime = show
        detailError = ""
        var cacheKey = _detailCacheKey(show, currentMode)
        if (detailCache[cacheKey]) {
            var cachedDetail = _deepClone(detailCache[cacheKey])
            cachedDetail.episodes = _normaliseEpisodeList(cachedDetail.episodes || [])
            currentAnime = Object.assign({}, show, cachedDetail)
            isFetchingDetail = false
            _maybeAutoPlayPendingShow(currentAnime)
            return
        }
        isFetchingDetail = true
        var showProviderId = _showMetadataProviderId(show)
        var showStreamProvider = _showStreamProviderId(show)
        Providers.metadata(showProviderId, "episodes", {
            showId: _showMetadataId(show),
            mode: currentMode,
            streamProvider: showStreamProvider
        }, function(err, d) {
            isFetchingDetail = false
            if (err) { detailError = err; return }
            if (!d) return
            if (show) {
                var preserveLocalId = String(((show.providerRefs || {}).metadata || {}).id || "") !== String(show.id || "")
                var enriched = Object.assign({}, show, d)
                if (preserveLocalId) enriched.id = show.id
                enriched.episodes = _normaliseEpisodeList(d.episodes || [])
                if (d.providerRefs) enriched.providerRefs = _deepClone(d.providerRefs)
                detailError = d.mappingError || ""
                detailCache[cacheKey] = _deepClone(enriched)
                currentAnime = enriched
                _maybeAutoPlayPendingShow(enriched)
            }
        })
    }

    function clearDetail() {
        currentAnime = null
        detailFocusEpisodeNum = ""
        pendingAutoPlayShowId = ""
    }

    function fetchStreamLinks(showId, epId, epNum) {
        if (!currentAnime) return
        _playingShowId  = showId
        _playingEpNum   = String(epNum)
        _pendingEpisodeId = String(epId || "")
        currentEpisode  = String(epNum)
        linksError      = ""
        playbackError   = ""
        selectedLink    = null
        isFetchingLinks = true
        var showStreamProvider = _showStreamProviderId(currentAnime)
        Providers.stream(showStreamProvider, "resolve", {
            showId: _showMetadataId(currentAnime),
            episodeNumber: String(epNum || ""),
            mode: currentMode,
            mirrorPref: preferredProvider,
            qualityPref: "best",
            title: _showTitle(currentAnime),
            metadataProviderId: _showMetadataProviderId(currentAnime)
        }, function(err, d) {
            isFetchingLinks = false
            if (err) { linksError = err; return }
            if (d && d.error) { linksError = d.error; return }
            selectedLink = d
        })
    }

    function clearStreamLinks() {
        selectedLink   = null
        linksError     = ""
        currentEpisode = ""
        _pendingEpisodeId = ""
    }
}
