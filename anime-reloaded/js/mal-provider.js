// mal-provider.js — MyAnimeList sync provider for AnimeReloaded
// Ports: mal_backend.py (backend proxy XHR), mal_client.py (MAL API + PKCE), mal_sync.py (push/pull/delete/auth)

var _MAL_AUTH_BASE = "https://myanimelist.net/v1/oauth2";
var _MAL_API_BASE = "https://api.myanimelist.net/v2";
var _MAL_AGENT = "AnimeReloaded/3.0";
var _MAL_BACKEND_URL = "https://dns.bogglemind.top:8443";
var _MAL_LEGACY_URLS = { "https://auth.bogglemind.top": true, "https://auth.bogglemind.top:8443": true };
var _MAL_BROWSER_AUTH_TIMEOUT = 240;
var _MAL_VERIFIER_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";

// --- GraphQL queries for AniList↔MAL ID mapping ---

var _MAL_Q_ANILIST_MAL_ID = "query($id:Int){Media(id:$id,type:ANIME){id idMal}}";
var _MAL_Q_ANILIST_MEDIA_BY_MAL_ID = "query($idMal:Int){Media(idMal:$idMal,type:ANIME){id idMal title{romaji english native} synonyms season seasonYear status episodes format averageScore genres nextAiringEpisode{episode airingAt timeUntilAiring} coverImage{large medium} startDate{year month day}}}";
var _MAL_Q_ANILIST_MEDIA_BY_MAL_IDS = "query($ids:[Int]){Page(page:1,perPage:50){media(idMal_in:$ids,type:ANIME){id idMal title{romaji english native} synonyms season seasonYear status episodes format averageScore genres nextAiringEpisode{episode airingAt timeUntilAiring} coverImage{large medium} startDate{year month day}}}}";

// --- Utility helpers ---

function _malParseInt(value) {
    try { return parseInt(parseFloat(String(value || "0").trim())); }
    catch (e) { return 0; }
}

function _malNormaliseListStatus(value) {
    var status = (value || "").trim().toLowerCase();
    if (status === "plan_to_watch" || status === "watching" || status === "completed" ||
        status === "on_hold" || status === "dropped") return status;
    return "";
}

function _malNormaliseUserAction(value) {
    var action = (value || "").trim().toLowerCase();
    if (action === "play" || action === "pause" || action === "drop" || action === "complete") return action;
    return "";
}

function _malNormaliseEpisodeCount(value) {
    var parsed = _malParseInt(value);
    return parsed > 0 ? parsed : 0;
}

function _malLocalWatchedEpisodes(entry) {
    var watched = 0;
    watched = Math.max(watched, _malParseInt((entry || {}).lastWatchedEpNum));
    var episodes = (entry || {}).watchedEpisodes || [];
    for (var i = 0; i < episodes.length; i++)
        watched = Math.max(watched, _malParseInt(episodes[i]));
    return watched;
}

function _malHasSavedProgress(entry) {
    var progress = (entry || {}).episodeProgress || {};
    var keys = Object.keys(progress);
    for (var i = 0; i < keys.length; i++) {
        var val = progress[keys[i]];
        var position = (typeof val === "object") ? _malParseInt(val.position) : _malParseInt(val);
        if (position > 0) return true;
    }
    return false;
}

function _malStatusSignalWatchedEpisodes(entry) {
    var watched = _malLocalWatchedEpisodes(entry);
    if (watched <= 0 && _malHasSavedProgress(entry)) watched = 1;
    return watched;
}

// --- Status computation (mirrors Python update_anime_status) ---

function _malUpdateAnimeStatus(opts) {
    var status = _malNormaliseListStatus(opts.currentStatus || "");
    var watched = _malNormaliseEpisodeCount(opts.watchedEpisodes || 0);
    var total = _malNormaliseEpisodeCount(opts.totalEpisodes || 0);
    var action = _malNormaliseUserAction(opts.userAction || "");

    if (total > 0 && watched > total) watched = total;

    if (action === "complete") {
        if (total > 0) watched = total;
        return { status: "completed", watchedEpisodes: watched };
    }
    if (action === "pause") return { status: "on_hold", watchedEpisodes: watched };
    if (action === "drop") return { status: "dropped", watchedEpisodes: watched };
    if (action === "play") {
        if (watched <= 0) return { status: "plan_to_watch", watchedEpisodes: 0 };
        if (total > 0 && watched >= total) return { status: "completed", watchedEpisodes: total };
        return { status: "watching", watchedEpisodes: watched };
    }
    if (status === "on_hold" || status === "dropped") return { status: status, watchedEpisodes: watched };
    if (watched <= 0) return { status: "plan_to_watch", watchedEpisodes: 0 };
    if (total > 0 && watched >= total) return { status: "completed", watchedEpisodes: total };
    if (status === "completed" && total <= 0) return { status: "completed", watchedEpisodes: watched };
    return { status: "watching", watchedEpisodes: watched };
}

// --- Config normalisation ---

function _malNormaliseConfig(raw) {
    var source = raw || {};
    var backendUrl = (source.backendUrl || "").trim().replace(/\/+$/, "");
    if (!backendUrl || _MAL_LEGACY_URLS[backendUrl]) backendUrl = _MAL_BACKEND_URL;

    return {
        version: 2,
        enabled: source.enabled === true,
        autoPush: source.autoPush === true,
        backendUrl: backendUrl,
        backendAuthSessionId: (source.backendAuthSessionId || "").trim(),
        backendSessionToken: (source.backendSessionToken || "").trim(),
        accessToken: (source.accessToken || "").trim(),
        tokenType: (source.tokenType || "Bearer").trim() || "Bearer",
        expiresAt: parseInt(source.expiresAt) || 0,
        userName: (source.userName || "").trim(),
        userPicture: (source.userPicture || "").trim(),
        lastSyncAt: parseInt(source.lastSyncAt) || 0,
        lastSyncDirection: (source.lastSyncDirection || "").trim()
    };
}

function _malApplyBackendTokenPayload(config, tokenPayload) {
    config = _malNormaliseConfig(config);
    var payload = tokenPayload || {};
    config.accessToken = (payload.accessToken || payload.access_token || "").trim();
    config.tokenType = (payload.tokenType || payload.token_type || "Bearer").trim() || "Bearer";
    var expiresAt = parseInt(payload.expiresAt) || 0;
    if (expiresAt <= 0) {
        var expiresIn = parseInt(payload.expiresIn || payload.expires_in) || 0;
        config.expiresAt = expiresIn > 0 ? Math.floor(Date.now() / 1000) + expiresIn : 0;
    } else {
        config.expiresAt = expiresAt;
    }
    return config;
}

function _malConfigForSave(config) {
    return _malNormaliseConfig(config);
}

function _malUsingBackend(config) {
    return !!((config || {}).backendUrl || "").trim();
}

// --- Backend proxy XHR (replaces mal_backend.py) ---

function _malBackendRequest(baseUrl, method, path, payload, callback) {
    var root = (baseUrl || "").trim().replace(/\/+$/, "");
    if (!root) { callback("MAL backend URL is not configured."); return; }

    var url = root + path;
    var xhr = new XMLHttpRequest();
    xhr.open(method.toUpperCase(), url, true);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("User-Agent", _MAL_AGENT);
    xhr.timeout = 20000;

    var body = null;
    if (payload !== undefined && payload !== null) {
        xhr.setRequestHeader("Content-Type", "application/json");
        body = JSON.stringify(payload);
    }

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) return;
        if (xhr.status >= 200 && xhr.status < 300) {
            try {
                var parsed = xhr.responseText ? JSON.parse(xhr.responseText) : {};
                callback(null, parsed);
            } catch (e) { callback("MAL backend parse error: " + e); }
        } else {
            var responseText = xhr.responseText || "";
            var message = "Backend request failed (HTTP " + xhr.status + ")";
            try {
                var errPayload = responseText ? JSON.parse(responseText) : {};
                message = (errPayload.error || errPayload.message || message).trim();
            } catch (e) {}
            callback(message);
        }
    };
    xhr.send(body);
}

function _malBackendStartAuth(baseUrl, callback) {
    _malBackendRequest(baseUrl, "POST", "/api/v1/mal/auth/start", {}, callback);
}

function _malBackendAwaitAuthSession(baseUrl, sessionId, timeoutSeconds, callback) {
    sessionId = (sessionId || "").trim();
    if (!sessionId) { callback("MAL backend auth session id is missing."); return; }

    var path = "/api/v1/mal/auth/session/" + encodeURIComponent(sessionId);
    var deadline = Date.now() + Math.max(15000, (timeoutSeconds || 240) * 1000);

    function poll() {
        if (Date.now() >= deadline) { callback("Timed out waiting for MAL backend login to finish."); return; }
        _malBackendRequest(baseUrl, "GET", path, undefined, function(err, payload) {
            if (err) { callback(err); return; }
            var status = ((payload || {}).status || "").trim().toLowerCase();
            if (status === "complete" || status === "completed" || status === "connected") {
                if (!((payload.sessionToken || "").trim()))
                    { callback("MAL backend login completed without a usable session token."); return; }
                if (!((payload.accessToken || payload.access_token || "").trim()))
                    { callback("MAL backend login completed without a usable access token."); return; }
                callback(null, payload);
                return;
            }
            if (status === "error") {
                callback((payload.error || "MAL backend login failed.").trim());
                return;
            }
            // QML JS has no setTimeout — XHR round-trip provides natural ~200-500ms delay
            poll();
        });
    }
    poll();
}

function _malBackendRefreshSession(baseUrl, sessionToken, callback) {
    var token = (sessionToken || "").trim();
    if (!token) { callback("MAL backend session token is missing."); return; }
    _malBackendRequest(baseUrl, "POST", "/api/v1/mal/auth/refresh", { sessionToken: token }, callback);
}

// --- MAL API XHR (replaces mal_client.py) ---

function _malIsContentFilter(errorMsg, errorBody) {
    var haystack = ((errorMsg || "") + " " + (errorBody || "")).toLowerCase();
    return haystack.indexOf("inappropriate content") !== -1;
}

function _malApiRequest(method, path, accessToken, params, data, callback) {
    var token = (accessToken || "").trim();
    if (!token) { callback("MAL access token is missing."); return; }

    var queryString = "";
    if (params) {
        var parts = [];
        var keys = Object.keys(params);
        for (var i = 0; i < keys.length; i++) {
            var val = params[keys[i]];
            if (val !== undefined && val !== null && val !== "") parts.push(encodeURIComponent(keys[i]) + "=" + encodeURIComponent(val));
        }
        queryString = parts.join("&");
    }

    var url = _MAL_API_BASE + path;
    if (queryString) url += "?" + queryString;

    var xhr = new XMLHttpRequest();
    xhr.open(method.toUpperCase(), url, true);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("User-Agent", _MAL_AGENT);
    xhr.setRequestHeader("Authorization", "Bearer " + token);
    xhr.timeout = 20000;

    var body = null;
    if (data !== undefined && data !== null) {
        var formParts = [];
        var dKeys = Object.keys(data);
        for (var d = 0; d < dKeys.length; d++)
            formParts.push(encodeURIComponent(dKeys[d]) + "=" + encodeURIComponent(data[dKeys[d]]));
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        body = formParts.join("&");
    }

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) return;
        if (xhr.status >= 200 && xhr.status < 300) {
            try {
                callback(null, xhr.responseText ? JSON.parse(xhr.responseText) : {});
            } catch (e) { callback("MAL API parse error: " + e); }
        } else if (xhr.status === 404 && method.toUpperCase() === "DELETE") {
            callback(null, {});
        } else {
            var responseText = xhr.responseText || "";
            var code = "", message = "MAL request failed (HTTP " + xhr.status + ")";
            try {
                var errPayload = responseText ? JSON.parse(responseText) : {};
                code = (errPayload.error || errPayload.code || "").trim();
                message = (errPayload.message || errPayload.error_description || message).trim();
            } catch (e) {}
            var fullError = new Error(code ? code + ": " + message : message);
            fullError._isMalApiError = true;
            fullError._isContentFilter = _malIsContentFilter(message, responseText);
            fullError._statusCode = xhr.status;
            callback(fullError);
        }
    };
    xhr.send(body);
}

function _malGetMe(accessToken, callback) {
    _malApiRequest("GET", "/users/@me", accessToken, { fields: "picture" }, undefined, callback);
}

function _malGetAnimeStatus(accessToken, animeId, callback) {
    _malApiRequest("GET", "/anime/" + parseInt(animeId), accessToken, {
        fields: "id,title,num_episodes,status,my_list_status,alternative_titles,start_season"
    }, undefined, callback);
}

function _malGetUserAnimelistPage(accessToken, username, status, limit, offset, callback) {
    var fields = ["list_status", "num_episodes", "status", "media_type", "start_season", "alternative_titles", "main_picture"];
    var params = {
        limit: Math.max(1, Math.min(1000, limit || 100)),
        offset: Math.max(0, offset || 0),
        fields: fields.join(",")
    };
    status = (status || "").trim().toLowerCase();
    if (status && status !== "all") params.status = status;

    var safeUser = (username || "@me").trim() || "@me";
    _malApiRequest("GET", "/users/" + encodeURIComponent(safeUser).replace("%40", "@") + "/animelist",
        accessToken, params, undefined, callback);
}

function _malGetUserAnimelist(accessToken, username, status, limit, callback) {
    var items = [];
    var offset = 0;
    var pageSize = Math.max(1, Math.min(1000, limit || 100));

    function fetchPage() {
        _malGetUserAnimelistPage(accessToken, username, status, pageSize, offset, function(err, payload) {
            if (err) { callback(err); return; }
            var pageItems = (payload || {}).data || [];
            if (!Array.isArray(pageItems) || pageItems.length === 0) { callback(null, items); return; }
            for (var i = 0; i < pageItems.length; i++) items.push(pageItems[i]);
            var paging = (payload || {}).paging || {};
            if (!paging.next) { callback(null, items); return; }
            offset += pageItems.length;
            fetchPage();
        });
    }
    fetchPage();
}

function _malUpdateAnimeListStatus(accessToken, animeId, status, numWatchedEpisodes, callback) {
    var payload = {};
    if (status) payload.status = String(status);
    if (numWatchedEpisodes !== undefined && numWatchedEpisodes !== null)
        payload.num_watched_episodes = String(Math.max(0, parseInt(numWatchedEpisodes) || 0));
    if (!Object.keys(payload).length) { callback("No MAL list fields provided to update."); return; }
    _malApiRequest("PUT", "/anime/" + parseInt(animeId) + "/my_list_status", accessToken, undefined, payload, callback);
}

function _malDeleteAnimeListStatus(accessToken, animeId, callback) {
    _malApiRequest("DELETE", "/anime/" + parseInt(animeId) + "/my_list_status", accessToken, undefined, undefined, callback);
}

// --- Ensure access token / authorised call ---

function _malEnsureAccessToken(config, callback) {
    config = _malNormaliseConfig(config);
    var accessToken = config.accessToken || "";
    var backendSessionToken = config.backendSessionToken || "";
    var expiresAt = parseInt(config.expiresAt) || 0;
    var nowTs = Math.floor(Date.now() / 1000);

    if (accessToken && (expiresAt <= 0 || expiresAt > (nowTs + 90))) {
        callback(null, config);
        return;
    }
    if (!_malUsingBackend(config)) { callback("MAL backend URL is not configured."); return; }
    if (!backendSessionToken) { callback("MAL backend session is missing. Connect the account first."); return; }

    _malBackendRefreshSession(config.backendUrl, backendSessionToken, function(err, tokenPayload) {
        if (err) { callback(err); return; }
        config = _malApplyBackendTokenPayload(config, tokenPayload);
        callback(null, config);
    });
}

function _malUpdateUserProfile(config, callback) {
    _malGetMe(config.accessToken || "", function(err, me) {
        if (!err && me) {
            config.userName = (me.name || config.userName || "").trim();
            config.userPicture = (me.picture || config.userPicture || "").trim();
        }
        callback(null, config);
    });
}

function _malAuthorisedCall(config, fn, callback) {
    _malEnsureAccessToken(config, function(err, config) {
        if (err) { callback(err); return; }
        fn(config, function(fnErr, result) {
            if (fnErr && fnErr._statusCode === 401 && config.backendSessionToken) {
                config.accessToken = "";
                config.tokenType = "Bearer";
                config.expiresAt = 0;
                _malEnsureAccessToken(config, function(err2, config2) {
                    if (err2) { callback(err2); return; }
                    fn(config2, function(fnErr2, result2) {
                        callback(fnErr2, config2, result2);
                    });
                });
            } else {
                callback(fnErr, config, result);
            }
        });
    });
}

// --- AniList MAL ID mapping ---

function _malAnilistMalId(metadataId, cache, callback) {
    var mediaId = (metadataId || "").trim();
    if (!mediaId || !/^\d+$/.test(mediaId)) { callback(null, ""); return; }
    if (cache[mediaId] !== undefined) { callback(null, cache[mediaId]); return; }

    _alGql(_MAL_Q_ANILIST_MAL_ID, { id: parseInt(mediaId) }, "mal-sync-idmal", 86400, function(err, data) {
        if (err) { callback(err); return; }
        var malId = String(((((data || {}).Media || {}).idMal) || "")).trim();
        cache[mediaId] = malId;
        callback(null, malId);
    });
}

function _malAnilistMediaFromMalId(malId, cache, callback) {
    var malKey = (malId || "").trim();
    if (!malKey || !/^\d+$/.test(malKey)) { callback(null, {}); return; }
    if (cache[malKey] !== undefined) { callback(null, cache[malKey]); return; }

    _alGql(_MAL_Q_ANILIST_MEDIA_BY_MAL_ID, { idMal: parseInt(malKey) }, "mal-sync-anilist-media", 86400, function(err, data) {
        if (err) { cache[malKey] = {}; callback(null, {}); return; }
        var media = (data || {}).Media || {};
        cache[malKey] = media;
        callback(null, media);
    });
}

function _malPrimeAnilistMediaCacheForMalIds(malIds, cache, doneCallback) {
    var pending = [];
    var seen = {};
    for (var i = 0; i < (malIds || []).length; i++) {
        var key = String(malIds[i] || "").trim();
        if (!key || !/^\d+$/.test(key) || seen[key] || cache[key] !== undefined) continue;
        seen[key] = true;
        pending.push(key);
    }

    var batchIndex = 0;

    function nextBatch() {
        if (batchIndex >= pending.length) { doneCallback(); return; }
        var batch = pending.slice(batchIndex, batchIndex + 50);
        batchIndex += 50;

        var ids = [];
        for (var b = 0; b < batch.length; b++) ids.push(parseInt(batch[b]));

        _alGql(_MAL_Q_ANILIST_MEDIA_BY_MAL_IDS, { ids: ids }, "mal-sync-anilist-media-batch", 86400, function(err, data) {
            if (!err) {
                var mediaList = (((data || {}).Page || {}).media) || [];
                for (var m = 0; m < mediaList.length; m++) {
                    var malKey = String((mediaList[m] || {}).idMal || "").trim();
                    if (malKey) cache[malKey] = mediaList[m];
                }
            }
            for (var k = 0; k < batch.length; k++) {
                if (cache[batch[k]] === undefined) cache[batch[k]] = {};
            }
            nextBatch();
        });
    }
    nextBatch();
}

// --- Entry helpers ---

function _malWithMalMapping(entry, malId) {
    var item = JSON.parse(JSON.stringify(entry || {}));
    var refs = item.providerRefs || {};
    refs.sync = { provider: "myanimelist", id: String(malId) };
    item.providerRefs = refs;
    return item;
}

function _malIdFromEntry(entry, anilistCache, callback) {
    var refs = (entry || {}).providerRefs || {};
    var syncRef = refs.sync || {};
    if ((syncRef.provider || "").trim() === "myanimelist" && syncRef.id) {
        var malId = String(syncRef.id);
        callback(null, malId, _malWithMalMapping(entry, malId));
        return;
    }
    var legacy = ((entry || {}).malId || "").trim();
    if (legacy) {
        callback(null, legacy, _malWithMalMapping(entry, legacy));
        return;
    }
    var metadataRef = refs.metadata || {};
    if ((metadataRef.provider || "").trim() === "anilist" && metadataRef.id) {
        _malAnilistMalId(metadataRef.id, anilistCache, function(err, malId) {
            if (err || !malId) { callback(null, "", JSON.parse(JSON.stringify(entry || {}))); return; }
            callback(null, malId, _malWithMalMapping(entry, malId));
        });
        return;
    }
    callback(null, "", JSON.parse(JSON.stringify(entry || {})));
}

function _malSyncReason(errMsg) {
    if (!errMsg) return "Unknown error";
    if (typeof errMsg === "string") return errMsg;
    return String(errMsg);
}

function _malEntryTitle(entry) {
    return ((entry || {}).englishName || (entry || {}).name || "").trim();
}

function _malEntryMetadataId(entry) {
    var refs = (entry || {}).providerRefs || {};
    var metadataRef = refs.metadata || {};
    var metadataId = (metadataRef.id || "").trim();
    if (metadataId) return metadataId;
    return ((entry || {}).id || "").trim();
}

function _malTotalEpisodeCount(entry, remotePayload) {
    var total = _malParseInt((entry || {}).episodeCount);
    if (total > 0) return total;
    total = _malParseInt((remotePayload || {}).num_episodes);
    if (total > 0) return total;
    var available = (entry || {}).availableEpisodes || {};
    return Math.max(_malParseInt(available.sub), _malParseInt(available.raw), _malParseInt(available.dub));
}

function _malRemoteWatchedEpisodes(payload) {
    var status = (payload || {}).my_list_status || (payload || {}).list_status || {};
    return Math.max(_malParseInt(status.num_episodes_watched), _malParseInt(status.num_watched_episodes));
}

function _malLocalStatus(entry, remotePayload) {
    var resolved = _malUpdateAnimeStatus({
        currentStatus: (entry || {}).listStatus,
        watchedEpisodes: _malStatusSignalWatchedEpisodes(entry),
        totalEpisodes: _malTotalEpisodeCount(entry, remotePayload)
    });
    return resolved.status;
}

function _malBuildMalPayload(animeId, status, watchedEpisodes) {
    var watched = _malNormaliseEpisodeCount(watchedEpisodes);
    var resolvedStatus = _malNormaliseListStatus(status);
    if (!resolvedStatus) resolvedStatus = watched > 0 ? "watching" : "plan_to_watch";
    if (resolvedStatus === "plan_to_watch") watched = 0;
    return { anime_id: String(animeId || "").trim(), status: resolvedStatus, num_watched_episodes: watched };
}

function _malRemoteStatusPayload(remoteEntry) {
    var item = JSON.parse(JSON.stringify(remoteEntry || {}));
    if (item.my_list_status) return item;
    var node = item.node || {};
    item.id = node.id || item.id;
    item.title = node.title || item.title;
    item.num_episodes = node.num_episodes || item.num_episodes;
    item.status = node.status || item.status;
    item.media_type = node.media_type || item.media_type;
    item.start_season = node.start_season || item.start_season;
    item.alternative_titles = node.alternative_titles || item.alternative_titles;
    item.main_picture = node.main_picture || item.main_picture;
    item.my_list_status = item.list_status || item.my_list_status || {};
    return item;
}

// --- Apply remote progress ---

function _malApplyRemoteProgress(entry, remotePayload) {
    var item = JSON.parse(JSON.stringify(entry || {}));
    var listStatus = (remotePayload || {}).my_list_status || {};
    var total = _malTotalEpisodeCount(item, remotePayload);
    var remoteStatus = _malNormaliseListStatus(listStatus.status);
    var remoteState = _malUpdateAnimeStatus({
        currentStatus: remoteStatus,
        watchedEpisodes: _malRemoteWatchedEpisodes(remotePayload),
        totalEpisodes: total,
        userAction: remoteStatus === "completed" ? "complete" : ""
    });
    var originalState = _malUpdateAnimeStatus({
        currentStatus: item.listStatus,
        watchedEpisodes: _malStatusSignalWatchedEpisodes(item),
        totalEpisodes: total
    });
    var watched = parseInt(remoteState.watchedEpisodes) || 0;
    var statusChanged = (
        originalState.status !== remoteState.status ||
        parseInt(originalState.watchedEpisodes || 0) !== watched
    );

    item.listStatus = remoteState.status || "plan_to_watch";
    item.lastWatchedEpId = "";

    if (watched <= 0) {
        item.lastWatchedEpNum = "";
        item.watchedEpisodes = [];
        item.episodeProgress = {};
        if (statusChanged) item.updatedAt = Math.floor(Date.now());
        return { item: item, changed: statusChanged };
    }

    var watchedEpisodes = [];
    for (var n = 1; n <= watched; n++) watchedEpisodes.push(String(n));

    var progress = JSON.parse(JSON.stringify(item.episodeProgress || {}));
    var progKeys = Object.keys(progress);
    for (var p = 0; p < progKeys.length; p++) {
        if (_malParseInt(progKeys[p]) <= watched) delete progress[progKeys[p]];
    }

    item.watchedEpisodes = watchedEpisodes;
    item.lastWatchedEpNum = String(watched);
    item.episodeProgress = progress;
    if (statusChanged) item.updatedAt = Math.floor(Date.now());
    return { item: item, changed: statusChanged };
}

// --- Import remote library entry ---

function _malImportRemoteLibraryEntry(remoteEntry, anilistCache, callback) {
    var remotePayload = _malRemoteStatusPayload(remoteEntry);
    var malId = String((remotePayload || {}).id || "").trim();
    if (!malId) { callback("MAL list entry is missing an anime id."); return; }

    _malAnilistMediaFromMalId(malId, anilistCache, function(err, media) {
        if (err) { callback(err); return; }
        if (!media || !media.id) { callback("No AniList metadata mapping available for this MAL title."); return; }

        var item = _alNormaliseMedia(media);
        var refs = item.providerRefs || {};
        refs.metadata = { provider: "anilist", id: String(item.id || "") };
        refs.sync = { provider: "myanimelist", id: malId };
        item.providerRefs = refs;
        item.lastWatchedEpId = "";
        item.lastWatchedEpNum = "";
        item.watchedEpisodes = [];
        item.episodeProgress = {};
        item.updatedAt = Math.floor(Date.now() / 1000);

        var applied = _malApplyRemoteProgress(item, remotePayload);
        callback(null, applied.item);
    });
}

// --- Known library IDs ---

function _malKnownLibraryIds(entries, anilistCache, callback) {
    var metadataIds = {};
    var malIds = {};
    var index = 0;

    function next() {
        if (index >= (entries || []).length) {
            var metaSet = [], malSet = [];
            var mKeys = Object.keys(metadataIds);
            for (var i = 0; i < mKeys.length; i++) metaSet.push(mKeys[i]);
            var malKeys = Object.keys(malIds);
            for (var j = 0; j < malKeys.length; j++) malSet.push(malKeys[j]);
            callback(null, metaSet, malSet);
            return;
        }
        var entry = entries[index++];
        var metadataId = _malEntryMetadataId(entry);
        if (metadataId) metadataIds[metadataId] = true;
        _malIdFromEntry(entry, anilistCache, function(err, malId, mappedEntry) {
            if (malId) malIds[malId] = true;
            next();
        });
    }
    next();
}

// --- Public API ---

function _malBuildAuthUrl(config, callback) {
    config = _malNormaliseConfig(config);
    if (!_malUsingBackend(config)) { callback("MAL backend URL is not configured."); return; }

    _malBackendStartAuth(config.backendUrl, function(err, payload) {
        if (err) { callback(err); return; }
        var authSessionId = (payload.authSessionId || "").trim();
        var authUrl = (payload.authUrl || "").trim();
        if (!authSessionId || !authUrl) { callback("MAL backend did not return a valid browser login session."); return; }
        config.backendAuthSessionId = authSessionId;
        callback(null, { config: _malConfigForSave(config), authUrl: authUrl });
    });
}

function _malAwaitBrowserLogin(config, timeoutSeconds, callback) {
    config = _malNormaliseConfig(config);
    var sessionId = (config.backendAuthSessionId || "").trim();
    if (!sessionId) { callback("Start MAL auth first so a backend browser session is available."); return; }

    _malBackendAwaitAuthSession(config.backendUrl, sessionId, timeoutSeconds || _MAL_BROWSER_AUTH_TIMEOUT, function(err, payload) {
        if (err) { callback(err); return; }
        config = _malApplyBackendTokenPayload(config, payload);
        var backendSessionToken = (payload.sessionToken || "").trim();
        if (!backendSessionToken) { callback("MAL backend login did not return a usable session token."); return; }
        if (!config.accessToken) { callback("MAL backend login did not return a usable access token."); return; }

        config.enabled = true;
        config.backendAuthSessionId = "";
        config.backendSessionToken = backendSessionToken;
        var user = payload.user || {};
        config.userName = (user.name || config.userName || "").trim();
        config.userPicture = (user.picture || config.userPicture || "").trim();

        callback(null, {
            config: _malConfigForSave(config),
            user: { name: config.userName, picture: config.userPicture }
        });
    });
}

function _malRefreshSession(config, callback) {
    _malEnsureAccessToken(config, function(err, config) {
        if (err) { callback(err); return; }
        _malUpdateUserProfile(config, function(profileErr, config) {
            callback(null, {
                config: _malConfigForSave(config),
                user: { name: config.userName, picture: config.userPicture }
            });
        });
    });
}

function _malPushLibrary(config, libraryEntries, callback) {
    config = _malNormaliseConfig(config);
    var results = [];
    var anilistCache = {};

    _malAuthorisedCall(config, function(currentConfig, authDone) {
        var pushed = 0, skipped = 0, failed = 0;
        var nextLibrary = [];
        var entries = libraryEntries || [];
        var entryIndex = 0;

        function processEntry() {
            if (entryIndex >= entries.length) {
                authDone(null, { library: nextLibrary, summary: { updated: pushed, skipped: skipped, failed: failed } });
                return;
            }
            var entry = entries[entryIndex++];
            _malIdFromEntry(entry, anilistCache, function(idErr, malId, mappedEntry) {
                nextLibrary.push(mappedEntry);
                if (!malId) {
                    skipped++;
                    results.push({
                        id: String((entry || {}).id || ""),
                        title: _malEntryTitle(entry),
                        status: "skipped",
                        reason: "No MyAnimeList mapping is available for this entry."
                    });
                    processEntry();
                    return;
                }

                var total = _malTotalEpisodeCount(entry);
                var state = _malUpdateAnimeStatus({
                    currentStatus: (entry || {}).listStatus,
                    watchedEpisodes: _malStatusSignalWatchedEpisodes(entry),
                    totalEpisodes: total
                });
                var payload = _malBuildMalPayload(malId, state.status, _malLocalWatchedEpisodes(entry));

                _malUpdateAnimeListStatus(currentConfig.accessToken, payload.anime_id, payload.status, payload.num_watched_episodes, function(updateErr, remote) {
                    if (updateErr) {
                        var errMsg = _malSyncReason(updateErr);
                        if (updateErr._isContentFilter) {
                            skipped++;
                            results.push({ id: String((entry || {}).id || ""), malId: malId, title: _malEntryTitle(entry), status: "skipped", reason: errMsg });
                        } else {
                            failed++;
                            results.push({ id: String((entry || {}).id || ""), malId: malId, title: _malEntryTitle(entry), status: "error", reason: errMsg });
                        }
                    } else {
                        pushed++;
                        results.push({
                            id: String((entry || {}).id || ""), malId: malId, title: _malEntryTitle(entry),
                            status: "updated", remoteStatus: String((remote || {}).status || payload.status),
                            watchedEpisodes: payload.num_watched_episodes
                        });
                    }
                    processEntry();
                });
            });
        }
        processEntry();
    }, function(err, finalConfig, payload) {
        if (err) { callback(err); return; }
        _malUpdateUserProfile(finalConfig, function(profileErr, profiledConfig) {
            profiledConfig.lastSyncAt = Math.floor(Date.now() / 1000);
            profiledConfig.lastSyncDirection = "push";
            payload.config = _malConfigForSave(profiledConfig);
            payload.results = results;
            callback(null, payload);
        });
    });
}

function _malRemoveAnimeEntry(config, malId, title, callback) {
    config = _malNormaliseConfig(config);
    malId = (malId || "").trim();
    title = (title || "").trim();
    if (!malId || !/^\d+$/.test(malId)) { callback("No MyAnimeList mapping is available for this title."); return; }

    _malAuthorisedCall(config, function(currentConfig, authDone) {
        _malDeleteAnimeListStatus(currentConfig.accessToken, malId, function(delErr) {
            if (delErr) { authDone(delErr); return; }
            authDone(null, { summary: { removed: 1, failed: 0 }, results: [{ malId: malId, title: title, status: "removed" }] });
        });
    }, function(err, finalConfig, payload) {
        if (err) { callback(err); return; }
        _malUpdateUserProfile(finalConfig, function(profileErr, profiledConfig) {
            profiledConfig.lastSyncAt = Math.floor(Date.now() / 1000);
            profiledConfig.lastSyncDirection = "delete";
            payload.config = _malConfigForSave(profiledConfig);
            callback(null, payload);
        });
    });
}

function _malPullLibrary(config, libraryEntries, callback) {
    config = _malNormaliseConfig(config);
    var results = [];
    var anilistCache = {};

    _malAuthorisedCall(config, function(currentConfig, authDone) {
        _malGetUserAnimelist(currentConfig.accessToken, "@me", "", 100, function(listErr, remoteEntries) {
            if (listErr) { authDone(listErr); return; }

            var remoteByMalId = {};
            for (var r = 0; r < (remoteEntries || []).length; r++) {
                var remotePayload = _malRemoteStatusPayload(remoteEntries[r]);
                var remoteMalId = String((remotePayload || {}).id || "").trim();
                if (remoteMalId) remoteByMalId[remoteMalId] = remotePayload;
            }

            var nextLibrary = [];
            var updated = 0, imported = 0, skipped = 0, failed = 0;
            var entries = libraryEntries || [];
            var entryIndex = 0;

            function processLocalEntry() {
                if (entryIndex >= entries.length) {
                    processRemoteOnly();
                    return;
                }
                var entry = entries[entryIndex++];
                _malIdFromEntry(entry, anilistCache, function(idErr, malId, mappedEntry) {
                    if (!malId) {
                        skipped++;
                        nextLibrary.push(mappedEntry);
                        results.push({ id: String((entry || {}).id || ""), title: _malEntryTitle(entry), status: "skipped", reason: "No MyAnimeList mapping is available for this entry." });
                        processLocalEntry();
                        return;
                    }

                    var remote = remoteByMalId[malId];
                    if (!remote) {
                        nextLibrary.push(mappedEntry);
                        results.push({ id: String((entry || {}).id || ""), malId: malId, title: _malEntryTitle(entry), status: "unchanged", reason: "This title is not present in the connected MAL library." });
                        processLocalEntry();
                        return;
                    }

                    var applied = _malApplyRemoteProgress(mappedEntry, remote);
                    nextLibrary.push(applied.item);
                    if (applied.changed) updated++;
                    results.push({
                        id: String((entry || {}).id || ""), malId: malId, title: _malEntryTitle(entry),
                        status: applied.changed ? "updated" : "unchanged",
                        remoteStatus: String(((remote.my_list_status || {}).status || "")),
                        watchedEpisodes: _malRemoteWatchedEpisodes(remote)
                    });
                    processLocalEntry();
                });
            }

            function processRemoteOnly() {
                // Build known sets
                var knownMetadataIds = {};
                var knownMalIds = {};
                for (var n = 0; n < nextLibrary.length; n++) {
                    var mid = _malEntryMetadataId(nextLibrary[n]);
                    if (mid) knownMetadataIds[mid] = true;
                    var sRef = ((nextLibrary[n] || {}).providerRefs || {}).sync || {};
                    if ((sRef.provider || "").trim() === "myanimelist" && sRef.id) knownMalIds[sRef.id] = true;
                }

                // Prime AniList cache for unmapped remote entries
                var unmappedMalIds = [];
                var remoteKeys = Object.keys(remoteByMalId);
                for (var u = 0; u < remoteKeys.length; u++) {
                    if (!knownMalIds[remoteKeys[u]]) unmappedMalIds.push(remoteKeys[u]);
                }

                _malPrimeAnilistMediaCacheForMalIds(unmappedMalIds, anilistCache, function() {
                    var importKeys = Object.keys(remoteByMalId).filter(function(k) { return !knownMalIds[k]; });
                    var importIndex = 0;

                    function processImport() {
                        if (importIndex >= importKeys.length) {
                            authDone(null, {
                                library: nextLibrary,
                                summary: { updated: updated, imported: imported, skipped: skipped, failed: failed }
                            });
                            return;
                        }
                        var malId = importKeys[importIndex++];
                        var remote = remoteByMalId[malId];

                        _malImportRemoteLibraryEntry(remote, anilistCache, function(impErr, importedEntry) {
                            if (impErr) {
                                skipped++;
                                results.push({ id: "", malId: malId, title: String((remote || {}).title || ""), status: "skipped", reason: _malSyncReason(impErr) });
                                processImport();
                                return;
                            }
                            var metadataId = _malEntryMetadataId(importedEntry);
                            if (metadataId && knownMetadataIds[metadataId]) {
                                results.push({ id: metadataId, malId: malId, title: _malEntryTitle(importedEntry), status: "unchanged", reason: "This AniList media is already present in the local library." });
                                processImport();
                                return;
                            }
                            nextLibrary.push(importedEntry);
                            imported++;
                            if (metadataId) knownMetadataIds[metadataId] = true;
                            knownMalIds[malId] = true;
                            results.push({
                                id: metadataId, malId: malId, title: _malEntryTitle(importedEntry),
                                status: "imported",
                                remoteStatus: String(((remote.my_list_status || {}).status || "")),
                                watchedEpisodes: _malRemoteWatchedEpisodes(remote)
                            });
                            processImport();
                        });
                    }
                    processImport();
                });
            }

            processLocalEntry();
        });
    }, function(err, finalConfig, payload) {
        if (err) { callback(err); return; }
        _malUpdateUserProfile(finalConfig, function(profileErr, profiledConfig) {
            profiledConfig.lastSyncAt = Math.floor(Date.now() / 1000);
            profiledConfig.lastSyncDirection = "pull";
            payload.config = _malConfigForSave(profiledConfig);
            payload.results = results;
            callback(null, payload);
        });
    });
}
