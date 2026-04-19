// anilist-sync-provider.js — AniList account sync provider for AnimeReloaded

var _ALS_AUTH_BASE = "https://anilist.co/api/v2/oauth/authorize";
var _ALS_API = "https://graphql.anilist.co";
var _ALS_AGENT = "AnimeReloaded/3.0";
var _ALS_DEFAULT_REDIRECT_URI = "https://anilist.co/api/v2/oauth/pin";

var _ALS_Q_VIEWER = "query{Viewer{id name avatar{large medium}}}";
var _ALS_Q_MEDIA_LIST_ENTRY = "query($mediaId:Int){Media(id:$mediaId,type:ANIME){id mediaListEntry{id status progress updatedAt}}}";
var _ALS_Q_MEDIA_LIST_COLLECTION = "query($userId:Int,$chunk:Int,$perChunk:Int){MediaListCollection(userId:$userId,type:ANIME,chunk:$chunk,perChunk:$perChunk,forceSingleCompletedList:true,status_in:[CURRENT,PLANNING,COMPLETED,DROPPED,PAUSED,REPEATING]){lists{name status entries{id status progress updatedAt media{id idMal title{romaji english native} synonyms season seasonYear status episodes format averageScore genres nextAiringEpisode{episode airingAt timeUntilAiring} coverImage{large medium} startDate{year month day}}}} user{id name avatar{large medium}} hasNextChunk}}";
var _ALS_M_SAVE = "mutation($mediaId:Int,$status:MediaListStatus,$progress:Int){SaveMediaListEntry(mediaId:$mediaId,status:$status,progress:$progress){id status progress updatedAt media{id episodes title{romaji english native}}}}";
var _ALS_M_DELETE = "mutation($id:Int){DeleteMediaListEntry(id:$id){deleted}}";

function _alsParseInt(value) {
    try { return parseInt(parseFloat(String(value || "0").trim())); }
    catch (e) { return 0; }
}

function _alsNormaliseConfig(raw) {
    var source = raw || {};
    return {
        version: 1,
        enabled: source.enabled === true,
        autoPush: source.autoPush === true,
        clientId: String(source.clientId || "").trim(),
        redirectUri: String(source.redirectUri || _ALS_DEFAULT_REDIRECT_URI).trim() || _ALS_DEFAULT_REDIRECT_URI,
        accessToken: String(source.accessToken || "").trim(),
        tokenType: "Bearer",
        userId: _alsParseInt(source.userId || 0),
        userName: String(source.userName || "").trim(),
        userPicture: String(source.userPicture || "").trim(),
        lastSyncAt: _alsParseInt(source.lastSyncAt || 0),
        lastSyncDirection: String(source.lastSyncDirection || "").trim()
    };
}

function _alsConfigForSave(config) {
    return _alsNormaliseConfig(config);
}

function _alsRequest(query, variables, accessToken, callback) {
    var token = String(accessToken || "").trim();
    if (!token) { callback("AniList access token is missing."); return; }

    var xhr = new XMLHttpRequest();
    xhr.open("POST", _ALS_API, true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("User-Agent", _ALS_AGENT);
    xhr.setRequestHeader("Authorization", "Bearer " + token);
    xhr.timeout = 20000;

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) return;

        var parsed = {};
        try { parsed = xhr.responseText ? JSON.parse(xhr.responseText) : {}; }
        catch (e) {}

        var errors = parsed.errors || [];
        if (xhr.status >= 200 && xhr.status < 300 && errors.length === 0) {
            callback(null, parsed.data || {});
            return;
        }

        var parts = [];
        for (var i = 0; i < errors.length; i++) {
            var msg = String((errors[i] || {}).message || "").trim();
            if (msg) parts.push(msg);
        }
        var message = parts.join("; ").trim();
        if (!message)
            message = xhr.status === 401 ? "AniList authorization failed." : ("AniList request failed (HTTP " + xhr.status + ")");
        callback(message);
    };

    xhr.send(JSON.stringify({
        query: query,
        variables: variables || {}
    }));
}

function _alsViewerProfile(accessToken, callback) {
    _alsRequest(_ALS_Q_VIEWER, {}, accessToken, function(err, data) {
        if (err) { callback(err); return; }
        var viewer = (data || {}).Viewer || {};
        callback(null, {
            id: _alsParseInt(viewer.id || 0),
            name: String(viewer.name || "").trim(),
            picture: String(((viewer.avatar || {}).large || (viewer.avatar || {}).medium || "")).trim()
        });
    });
}

function _alsApplyProfile(config, profile) {
    config = _alsNormaliseConfig(config);
    var user = profile || {};
    config.enabled = true;
    config.userId = _alsParseInt(user.id || 0);
    config.userName = String(user.name || "").trim();
    config.userPicture = String(user.picture || "").trim();
    return config;
}

function _alsJwtLikeToken(value) {
    return /^[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+$/.test(String(value || "").trim());
}

function _alsExtractAccessToken(value) {
    var text = String(value || "").trim();
    if (!text) return "";
    if (_alsJwtLikeToken(text)) return text;

    var match = text.match(/(?:[#?&]access_token=)([^&#\s]+)/i);
    if (match && match[1]) return decodeURIComponent(match[1]).trim();

    match = text.match(/access_token(?:=|:)\s*([A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+)/i);
    if (match && match[1]) return String(match[1]).trim();

    return "";
}

function _alsLocalWatchedEpisodes(entry) {
    var watched = Math.max(0, _alsParseInt((entry || {}).lastWatchedEpNum));
    var watchedEpisodes = Array.isArray((entry || {}).watchedEpisodes) ? entry.watchedEpisodes : [];
    for (var i = 0; i < watchedEpisodes.length; i++)
        watched = Math.max(watched, _alsParseInt(watchedEpisodes[i]));
    return watched;
}

function _alsHasSavedProgress(entry) {
    var progress = ((entry || {}).episodeProgress && typeof (entry || {}).episodeProgress === "object")
        ? entry.episodeProgress
        : {};
    var keys = Object.keys(progress);
    for (var i = 0; i < keys.length; i++) {
        var item = progress[keys[i]];
        var position = (typeof item === "object") ? _alsParseInt(item.position) : _alsParseInt(item);
        if (position > 0) return true;
    }
    return false;
}

function _alsStatusSignalWatchedEpisodes(entry) {
    var watched = _alsLocalWatchedEpisodes(entry);
    if (watched <= 0 && _alsHasSavedProgress(entry)) watched = 1;
    return watched;
}

function _alsTotalEpisodeCount(entry, media) {
    var total = _alsParseInt((entry || {}).episodeCount);
    if (total > 0) return total;
    total = _alsParseInt((media || {}).episodes);
    if (total > 0) return total;
    var available = (entry || {}).availableEpisodes || {};
    return Math.max(_alsParseInt(available.sub), _alsParseInt(available.raw), _alsParseInt(available.dub));
}

function _alsNormaliseLocalStatus(value) {
    var key = String(value || "").trim().toLowerCase();
    if (key === "watching" || key === "plan_to_watch" || key === "completed" || key === "on_hold" || key === "dropped")
        return key;
    return "";
}

function _alsResolveStatus(currentStatus, watchedEpisodes, totalEpisodes) {
    var status = _alsNormaliseLocalStatus(currentStatus);
    var watched = Math.max(0, _alsParseInt(watchedEpisodes));
    var total = Math.max(0, _alsParseInt(totalEpisodes));
    if (total > 0 && watched > total) watched = total;

    if (status === "on_hold" || status === "dropped")
        return { status: status, watchedEpisodes: watched };
    if (watched <= 0)
        return { status: "plan_to_watch", watchedEpisodes: 0 };
    if (total > 0 && watched >= total)
        return { status: "completed", watchedEpisodes: total };
    if (status === "completed" && total <= 0)
        return { status: "completed", watchedEpisodes: watched };
    return { status: "watching", watchedEpisodes: watched };
}

function _alsAniListStatus(localStatus, watchedEpisodes, totalEpisodes) {
    var resolved = _alsResolveStatus(localStatus, watchedEpisodes, totalEpisodes);
    var watched = Math.max(0, _alsParseInt(resolved.watchedEpisodes));
    var status = resolved.status;
    if (status === "completed") return { status: "COMPLETED", progress: watched };
    if (status === "watching") return { status: "CURRENT", progress: watched };
    if (status === "on_hold") return { status: "PAUSED", progress: watched };
    if (status === "dropped") return { status: "DROPPED", progress: watched };
    return { status: "PLANNING", progress: 0 };
}

function _alsLocalStatusFromRemote(remoteStatus, progress, totalEpisodes) {
    var remote = String(remoteStatus || "").trim().toUpperCase();
    if (remote === "COMPLETED")
        return _alsResolveStatus("completed", progress, totalEpisodes);
    if (remote === "PAUSED")
        return _alsResolveStatus("on_hold", progress, totalEpisodes);
    if (remote === "DROPPED")
        return _alsResolveStatus("dropped", progress, totalEpisodes);
    if (remote === "REPEATING")
        return _alsResolveStatus("watching", progress, totalEpisodes);
    if (remote === "CURRENT")
        return _alsResolveStatus("watching", progress, totalEpisodes);
    return _alsResolveStatus("plan_to_watch", 0, totalEpisodes);
}

function _alsEntryTitle(entry) {
    return String((entry || {}).englishName || (entry || {}).name || "").trim();
}

function _alsEntryMetadataId(entry) {
    var refs = (entry || {}).providerRefs || {};
    var metadataRef = refs.metadata || {};
    var id = String(metadataRef.id || "").trim();
    if (id) return id;
    return String((entry || {}).id || "").trim();
}

function _alsWithAniListMetadata(entry, mediaId) {
    var item = JSON.parse(JSON.stringify(entry || {}));
    var refs = item.providerRefs || {};
    refs.metadata = { provider: "anilist", id: String(mediaId || "").trim() };
    item.providerRefs = refs;
    return item;
}

function _alsResolveMediaId(entry, anilistCache, callback) {
    var metadataId = _alsEntryMetadataId(entry);
    var metadataProvider = String((((entry || {}).providerRefs || {}).metadata || {}).provider || "").trim();
    if (metadataId && /^\d+$/.test(metadataId) && (metadataProvider === "anilist" || metadataProvider.length === 0)) {
        callback(null, metadataId, _alsWithAniListMetadata(entry, metadataId));
        return;
    }

    var syncRef = (((entry || {}).providerRefs || {}).sync || {});
    var malId = String(syncRef.id || "").trim();
    if ((syncRef.provider || "").trim() === "myanimelist"
            && /^\d+$/.test(malId)
            && typeof _malAnilistMediaFromMalId === "function") {
        _malAnilistMediaFromMalId(malId, anilistCache || {}, function(err, media) {
            if (err) {
                callback(String(err), "", JSON.parse(JSON.stringify(entry || {})));
                return;
            }
            if (!media || !media.id) {
                callback(null, "", JSON.parse(JSON.stringify(entry || {})));
                return;
            }
            callback(null, String(media.id), _alsWithAniListMetadata(entry, media.id));
        });
        return;
    }

    callback(null, "", JSON.parse(JSON.stringify(entry || {})));
}

function _alsApplyRemoteProgress(entry, remoteEntry) {
    var item = JSON.parse(JSON.stringify(entry || {}));
    var media = (remoteEntry || {}).media || {};
    var total = _alsTotalEpisodeCount(item, media);
    var resolved = _alsLocalStatusFromRemote((remoteEntry || {}).status, (remoteEntry || {}).progress, total);
    var original = _alsResolveStatus((item || {}).listStatus, _alsStatusSignalWatchedEpisodes(item), total);
    var watched = Math.max(0, _alsParseInt(resolved.watchedEpisodes));
    var statusChanged = (
        String(original.status || "") !== String(resolved.status || "") ||
        _alsParseInt(original.watchedEpisodes || 0) !== watched
    );

    item.listStatus = resolved.status || "plan_to_watch";
    item.lastWatchedEpId = "";

    if (watched <= 0) {
        item.lastWatchedEpNum = "";
        item.watchedEpisodes = [];
        item.episodeProgress = {};
        if (statusChanged) item.updatedAt = Math.floor(Date.now() / 1000);
        return { item: item, changed: statusChanged };
    }

    var watchedEpisodes = [];
    for (var n = 1; n <= watched; n++) watchedEpisodes.push(String(n));

    var progress = JSON.parse(JSON.stringify(item.episodeProgress || {}));
    var progressKeys = Object.keys(progress);
    for (var i = 0; i < progressKeys.length; i++) {
        if (_alsParseInt(progressKeys[i]) <= watched)
            delete progress[progressKeys[i]];
    }

    item.watchedEpisodes = watchedEpisodes;
    item.lastWatchedEpNum = String(watched);
    item.episodeProgress = progress;
    if (statusChanged) item.updatedAt = Math.floor(Date.now() / 1000);
    return { item: item, changed: statusChanged };
}

function _alsImportRemoteLibraryEntry(remoteEntry, callback) {
    var media = (remoteEntry || {}).media || {};
    var mediaId = String(media.id || "").trim();
    if (!mediaId) { callback("AniList list entry is missing a media id."); return; }

    var item = _alNormaliseMedia(media);
    var refs = item.providerRefs || {};
    refs.metadata = { provider: "anilist", id: mediaId };
    item.providerRefs = refs;
    item.lastWatchedEpId = "";
    item.lastWatchedEpNum = "";
    item.watchedEpisodes = [];
    item.episodeProgress = {};
    item.updatedAt = Math.floor(Date.now() / 1000);

    var applied = _alsApplyRemoteProgress(item, remoteEntry);
    callback(null, applied.item);
}

function _alsListEntryTitle(remoteEntry) {
    var media = (remoteEntry || {}).media || {};
    var title = media.title || {};
    return String(title.english || title.romaji || title.native || "").trim();
}

function _alsRemoteProgress(remoteEntry) {
    return Math.max(0, _alsParseInt((remoteEntry || {}).progress));
}

function _alsGetMediaListEntry(accessToken, mediaId, callback) {
    if (!/^\d+$/.test(String(mediaId || "").trim())) {
        callback("AniList media id is missing.");
        return;
    }
    _alsRequest(_ALS_Q_MEDIA_LIST_ENTRY, { mediaId: parseInt(mediaId) }, accessToken, function(err, data) {
        if (err) { callback(err); return; }
        var media = (data || {}).Media || {};
        callback(null, (media.mediaListEntry || null));
    });
}

function _alsGetUserAnimelist(accessToken, userId, callback) {
    var items = [];
    var chunk = 1;
    var perChunk = 500;

    function nextChunk() {
        _alsRequest(_ALS_Q_MEDIA_LIST_COLLECTION, {
            userId: _alsParseInt(userId),
            chunk: chunk,
            perChunk: perChunk
        }, accessToken, function(err, data) {
            if (err) { callback(err); return; }
            var collection = (data || {}).MediaListCollection || {};
            var lists = collection.lists || [];
            for (var i = 0; i < lists.length; i++) {
                var entries = (lists[i] || {}).entries || [];
                for (var j = 0; j < entries.length; j++) {
                    if (((entries[j] || {}).media || {}).id)
                        items.push(entries[j]);
                }
            }
            if (collection.hasNextChunk === true) {
                chunk += 1;
                nextChunk();
                return;
            }
            callback(null, items);
        });
    }

    nextChunk();
}

function _anilistSyncBuildAuthUrl(config, callback) {
    config = _alsNormaliseConfig(config);
    if (!/^\d+$/.test(config.clientId)) {
        callback("Enter a valid AniList client id before starting browser login.");
        return;
    }

    var authUrl = _ALS_AUTH_BASE
        + "?client_id=" + encodeURIComponent(config.clientId)
        + "&response_type=token";
    // AniList's standard pin flow expects the redirect URI to be configured
    // on the client itself. Passing the default pin redirect explicitly can
    // lead to the wrong server behavior in-browser, so only include a custom
    // redirect URI when the user is intentionally overriding it.
    if (config.redirectUri && config.redirectUri !== _ALS_DEFAULT_REDIRECT_URI)
        authUrl += "&redirect_uri=" + encodeURIComponent(config.redirectUri);

    callback(null, {
        config: _alsConfigForSave(config),
        authUrl: authUrl
    });
}

function _anilistSyncConnectToken(config, authResult, callback) {
    config = _alsNormaliseConfig(config);
    var accessToken = _alsExtractAccessToken(authResult);
    if (!accessToken) {
        callback("Paste the AniList callback URL or the raw access token returned after login.");
        return;
    }

    _alsViewerProfile(accessToken, function(err, profile) {
        if (err) { callback(err); return; }
        config.accessToken = accessToken;
        config.tokenType = "Bearer";
        config = _alsApplyProfile(config, profile);
        callback(null, {
            config: _alsConfigForSave(config),
            user: {
                id: config.userId,
                name: config.userName,
                picture: config.userPicture
            }
        });
    });
}

function _anilistSyncRefresh(config, callback) {
    config = _alsNormaliseConfig(config);
    if (!config.accessToken) {
        callback("Connect an AniList account before refreshing.");
        return;
    }

    _alsViewerProfile(config.accessToken, function(err, profile) {
        if (err) { callback(err); return; }
        config = _alsApplyProfile(config, profile);
        callback(null, {
            config: _alsConfigForSave(config),
            user: {
                id: config.userId,
                name: config.userName,
                picture: config.userPicture
            }
        });
    });
}

function _anilistSyncPushLibrary(config, libraryEntries, callback) {
    config = _alsNormaliseConfig(config);
    if (!config.accessToken) {
        callback("Connect an AniList account before pushing library progress.");
        return;
    }

    var results = [];
    var anilistCache = {};

    _alsViewerProfile(config.accessToken, function(profileErr, profile) {
        if (profileErr) { callback(profileErr); return; }
        config = _alsApplyProfile(config, profile);

        var updated = 0, skipped = 0, failed = 0;
        var nextLibrary = [];
        var entries = libraryEntries || [];
        var index = 0;

        function nextEntry() {
            if (index >= entries.length) {
                config.lastSyncAt = Math.floor(Date.now() / 1000);
                config.lastSyncDirection = "push";
                callback(null, {
                    config: _alsConfigForSave(config),
                    library: nextLibrary,
                    summary: { updated: updated, skipped: skipped, failed: failed },
                    results: results
                });
                return;
            }

            var entry = entries[index++];
            _alsResolveMediaId(entry, anilistCache, function(idErr, mediaId, mappedEntry) {
                nextLibrary.push(mappedEntry);
                if (idErr) {
                    failed++;
                    results.push({
                        id: _alsEntryMetadataId(entry),
                        title: _alsEntryTitle(entry),
                        status: "error",
                        reason: String(idErr)
                    });
                    nextEntry();
                    return;
                }
                if (!mediaId) {
                    skipped++;
                    results.push({
                        id: _alsEntryMetadataId(entry),
                        title: _alsEntryTitle(entry),
                        status: "skipped",
                        reason: "No AniList metadata mapping is available for this entry."
                    });
                    nextEntry();
                    return;
                }

                var total = _alsTotalEpisodeCount(mappedEntry);
                var state = _alsAniListStatus((mappedEntry || {}).listStatus, _alsStatusSignalWatchedEpisodes(mappedEntry), total);

                _alsRequest(_ALS_M_SAVE, {
                    mediaId: parseInt(mediaId),
                    status: state.status,
                    progress: state.progress
                }, config.accessToken, function(saveErr, data) {
                    if (saveErr) {
                        failed++;
                        results.push({
                            id: mediaId,
                            title: _alsEntryTitle(mappedEntry),
                            status: "error",
                            reason: String(saveErr)
                        });
                    } else {
                        updated++;
                        var saved = (data || {}).SaveMediaListEntry || {};
                        results.push({
                            id: mediaId,
                            title: _alsEntryTitle(mappedEntry),
                            status: "updated",
                            remoteStatus: String(saved.status || state.status),
                            watchedEpisodes: _alsParseInt(saved.progress || state.progress)
                        });
                    }
                    nextEntry();
                });
            });
        }

        nextEntry();
    });
}

function _anilistSyncDeleteEntry(config, mediaId, title, callback) {
    config = _alsNormaliseConfig(config);
    mediaId = String(mediaId || "").trim();
    title = String(title || "").trim();
    if (!config.accessToken) {
        callback("Connect an AniList account before removing titles from your AniList list.");
        return;
    }
    if (!/^\d+$/.test(mediaId)) {
        callback("No AniList media id is available for this title.");
        return;
    }

    _alsViewerProfile(config.accessToken, function(profileErr, profile) {
        if (profileErr) { callback(profileErr); return; }
        config = _alsApplyProfile(config, profile);

        _alsGetMediaListEntry(config.accessToken, mediaId, function(entryErr, listEntry) {
            if (entryErr) { callback(entryErr); return; }
            if (!listEntry || !_alsParseInt(listEntry.id)) {
                callback(null, {
                    config: _alsConfigForSave(config),
                    summary: { removed: 0, failed: 0 },
                    results: [{ id: mediaId, title: title, status: "unchanged", reason: "This title is not present in the connected AniList library." }]
                });
                return;
            }

            _alsRequest(_ALS_M_DELETE, { id: _alsParseInt(listEntry.id) }, config.accessToken, function(delErr) {
                if (delErr) { callback(delErr); return; }
                config.lastSyncAt = Math.floor(Date.now() / 1000);
                config.lastSyncDirection = "delete";
                callback(null, {
                    config: _alsConfigForSave(config),
                    summary: { removed: 1, failed: 0 },
                    results: [{ id: mediaId, title: title, status: "removed" }]
                });
            });
        });
    });
}

function _anilistSyncPullLibrary(config, libraryEntries, callback) {
    config = _alsNormaliseConfig(config);
    if (!config.accessToken) {
        callback("Connect an AniList account before pulling progress.");
        return;
    }

    var results = [];
    var anilistCache = {};

    _alsViewerProfile(config.accessToken, function(profileErr, profile) {
        if (profileErr) { callback(profileErr); return; }
        config = _alsApplyProfile(config, profile);

        _alsGetUserAnimelist(config.accessToken, config.userId, function(listErr, remoteEntries) {
            if (listErr) { callback(listErr); return; }

            var remoteByMediaId = {};
            for (var r = 0; r < remoteEntries.length; r++) {
                var mediaId = String((((remoteEntries[r] || {}).media || {}).id) || "").trim();
                if (mediaId) remoteByMediaId[mediaId] = remoteEntries[r];
            }

            var nextLibrary = [];
            var updated = 0, imported = 0, skipped = 0, failed = 0;
            var knownMediaIds = {};
            var entries = libraryEntries || [];
            var index = 0;

            function processLocalEntry() {
                if (index >= entries.length) {
                    processRemoteOnly();
                    return;
                }

                var entry = entries[index++];
                _alsResolveMediaId(entry, anilistCache, function(idErr, mediaId, mappedEntry) {
                    nextLibrary.push(mappedEntry);
                    if (mediaId) knownMediaIds[mediaId] = true;
                    if (idErr) {
                        failed++;
                        results.push({
                            id: _alsEntryMetadataId(entry),
                            title: _alsEntryTitle(entry),
                            status: "error",
                            reason: String(idErr)
                        });
                        processLocalEntry();
                        return;
                    }

                    if (!mediaId) {
                        skipped++;
                        results.push({
                            id: _alsEntryMetadataId(entry),
                            title: _alsEntryTitle(entry),
                            status: "skipped",
                            reason: "No AniList metadata mapping is available for this entry."
                        });
                        processLocalEntry();
                        return;
                    }

                    var remote = remoteByMediaId[mediaId];
                    if (!remote) {
                        results.push({
                            id: mediaId,
                            title: _alsEntryTitle(mappedEntry),
                            status: "unchanged",
                            reason: "This title is not present in the connected AniList library."
                        });
                        processLocalEntry();
                        return;
                    }

                    var applied = _alsApplyRemoteProgress(mappedEntry, remote);
                    nextLibrary[nextLibrary.length - 1] = applied.item;
                    if (applied.changed) updated++;
                    results.push({
                        id: mediaId,
                        title: _alsEntryTitle(applied.item),
                        status: applied.changed ? "updated" : "unchanged",
                        remoteStatus: String((remote || {}).status || ""),
                        watchedEpisodes: _alsRemoteProgress(remote)
                    });
                    processLocalEntry();
                });
            }

            function processRemoteOnly() {
                var importIds = Object.keys(remoteByMediaId).filter(function(id) {
                    return !knownMediaIds[id];
                });
                var importIndex = 0;

                function nextImport() {
                    if (importIndex >= importIds.length) {
                        config.lastSyncAt = Math.floor(Date.now() / 1000);
                        config.lastSyncDirection = "pull";
                        callback(null, {
                            config: _alsConfigForSave(config),
                            library: nextLibrary,
                            summary: { updated: updated, imported: imported, skipped: skipped, failed: failed },
                            results: results
                        });
                        return;
                    }

                    var mediaId = importIds[importIndex++];
                    var remote = remoteByMediaId[mediaId];

                    _alsImportRemoteLibraryEntry(remote, function(importErr, importedEntry) {
                        if (importErr) {
                            failed++;
                            results.push({
                                id: mediaId,
                                title: _alsListEntryTitle(remote),
                                status: "error",
                                reason: String(importErr)
                            });
                            nextImport();
                            return;
                        }

                        var metadataId = _alsEntryMetadataId(importedEntry);
                        if (metadataId && knownMediaIds[metadataId]) {
                            results.push({
                                id: metadataId,
                                title: _alsEntryTitle(importedEntry),
                                status: "unchanged",
                                reason: "This AniList media is already present in the local library."
                            });
                            nextImport();
                            return;
                        }

                        nextLibrary.push(importedEntry);
                        imported++;
                        if (metadataId) knownMediaIds[metadataId] = true;
                        results.push({
                            id: metadataId,
                            title: _alsEntryTitle(importedEntry),
                            status: "imported",
                            remoteStatus: String((remote || {}).status || ""),
                            watchedEpisodes: _alsRemoteProgress(remote)
                        });
                        nextImport();
                    });
                }

                nextImport();
            }

            processLocalEntry();
        });
    });
}
