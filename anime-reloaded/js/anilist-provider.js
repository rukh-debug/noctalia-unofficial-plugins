var _AL_API = "https://graphql.anilist.co";
var _AL_AGENT = "AnimeReloaded/3.0";
var _AL_cache = null;
var _AL_lastRequestAt = 0;
var _AL_MIN_GAP = 350;
var _AL_MAX_ENTRIES = 512;
var _AL_pendingRequests = [];

var _AL_Q_GENRES = "query{GenreCollection}";
var _AL_Q_PAGE_BASE = "query($page:Int,$perPage:Int,$search:String,$sort:[MediaSort]){Page(page:$page,perPage:$perPage){pageInfo{hasNextPage}media(type:ANIME,search:$search,sort:$sort,isAdult:false){id idMal title{romaji english native} synonyms season seasonYear status episodes format averageScore genres nextAiringEpisode{episode airingAt timeUntilAiring} coverImage{large medium} startDate{year month day}}}}";
var _AL_Q_PAGE_GENRE = "query($page:Int,$perPage:Int,$search:String,$sort:[MediaSort],$genre:String){Page(page:$page,perPage:$perPage){pageInfo{hasNextPage}media(type:ANIME,search:$search,sort:$sort,genre:$genre,isAdult:false){id idMal title{romaji english native} synonyms season seasonYear status episodes format averageScore genres nextAiringEpisode{episode airingAt timeUntilAiring} coverImage{large medium} startDate{year month day}}}}";
var _AL_Q_PAGE_RELEASING = "query($page:Int,$perPage:Int,$search:String,$sort:[MediaSort]){Page(page:$page,perPage:$perPage){pageInfo{hasNextPage}media(type:ANIME,search:$search,sort:$sort,status:RELEASING,isAdult:false){id idMal title{romaji english native} synonyms season seasonYear status episodes format averageScore genres nextAiringEpisode{episode airingAt timeUntilAiring} coverImage{large medium} startDate{year month day}}}}";
var _AL_Q_MEDIA = "query($id:Int){Media(id:$id,type:ANIME){id idMal title{romaji english native} synonyms description(asHtml:false) episodes duration status format season seasonYear averageScore genres bannerImage coverImage{extraLarge large medium color} startDate{year month day} endDate{year month day} nextAiringEpisode{episode airingAt timeUntilAiring} relations{edges{relationType}nodes{id title{romaji english native} status format season seasonYear}}}}";
var _AL_Q_RELATION_STEP = "query($id:Int){Media(id:$id,type:ANIME){id idMal title{romaji english native} status format season seasonYear coverImage{large medium} relations{edges{relationType}nodes{id title{romaji english native} status format season seasonYear}}}}";
var _AL_Q_FEED_BATCH = "query($ids:[Int]){Page(page:1,perPage:50){media(id_in:$ids,type:ANIME){id idMal title{romaji english native} synonyms status episodes format averageScore season seasonYear nextAiringEpisode{episode airingAt timeUntilAiring} coverImage{large medium} startDate{year month day}}}}";

var _AL_SEASON_RELATION_TYPES = { PREQUEL: true, SEQUEL: true };
var _AL_SEASON_FORMATS = { TV: true, TV_SHORT: true, ONA: true, OVA: true, SPECIAL: true };
var _AL_SEASON_ORDER = { WINTER: 1, SPRING: 2, SUMMER: 3, FALL: 4 };

function _alLoadCache() {
    if (_AL_cache !== null) return _AL_cache;
    _AL_cache = { version: 1, entries: {}, cooldownUntil: 0 };
    return _AL_cache;
}

function _alSha256Hex(str) {
    var bytes = new Uint8Array(str.length);
    for (var i = 0; i < str.length; i++) bytes[i] = str.charCodeAt(i);
    return CryptoHelper.bytesToHex(CryptoHelper.sha256(bytes));
}

function _alCacheKey(scope, query, variables) {
    var filtered = {};
    if (variables) {
        var keys = Object.keys(variables);
        for (var i = 0; i < keys.length; i++) {
            if (variables[keys[i]] !== undefined && variables[keys[i]] !== null)
                filtered[keys[i]] = variables[keys[i]];
        }
    }
    return _alSha256Hex(JSON.stringify({ s: scope || "", q: query || "", v: filtered }));
}

function _alGetEntry(key) {
    return ((_alLoadCache().entries || {})[key]) || {};
}

function _alGetCachedData(key, ttl, now) {
    var entry = _alGetEntry(key);
    var cachedAt = parseInt(entry.cachedAt) || 0;
    var data = entry.data;
    if (cachedAt <= 0 || typeof data !== "object") return null;
    if (ttl > 0 && (now - cachedAt) > ttl) return null;
    return data;
}

function _alGetStaleData(key) {
    var entry = _alGetEntry(key);
    return (typeof entry.data === "object") ? entry.data : null;
}

function _alStoreData(key, data, now) {
    var cache = _alLoadCache();
    cache.entries[key] = { cachedAt: Math.floor(now), data: data };
    var entries = cache.entries;
    var keys = Object.keys(entries);
    if (keys.length > _AL_MAX_ENTRIES) {
        keys.sort(function(a, b) { return (parseInt(entries[b].cachedAt) || 0) - (parseInt(entries[a].cachedAt) || 0); });
        var pruned = {};
        for (var i = 0; i < _AL_MAX_ENTRIES; i++) pruned[keys[i]] = entries[keys[i]];
        cache.entries = pruned;
    }
}

function _alGql(query, variables, cacheScope, ttlSeconds, callback) {
    var key = _alCacheKey(cacheScope || "", query, variables || {});
    var nowTs = Date.now() / 1000;
    var cached = _alGetCachedData(key, ttlSeconds || 300, nowTs);
    if (cached) { callback(null, cached); return; }

    var cache = _alLoadCache();
    var cooldownUntil = parseInt(cache.cooldownUntil) || 0;
    var stale = _alGetStaleData(key);
    if (cooldownUntil > nowTs && stale) { callback(null, stale); return; }

    // QML JS has no setTimeout — fire immediately. XHR round-trip provides natural rate limiting.
    _alDoGql(query, variables, key, ttlSeconds, callback);
}

function _alDoGql(query, variables, key, ttlSeconds, callback) {
    _AL_lastRequestAt = Date.now();
    var xhr = new XMLHttpRequest();
    xhr.open("POST", _AL_API, true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("User-Agent", _AL_AGENT);
    xhr.timeout = 20000;

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) return;
        _AL_lastRequestAt = Date.now();
        if (xhr.status >= 200 && xhr.status < 300) {
            try {
                var parsed = JSON.parse(xhr.responseText);
                if (parsed.errors && parsed.errors.length) {
                    var msgs = [];
                    for (var i = 0; i < parsed.errors.length; i++)
                        msgs.push(parsed.errors[i].message || "Unknown AniList error");
                    callback(msgs.join("; "));
                    return;
                }
                var data = parsed.data || {};
                _alStoreData(key, data, Date.now() / 1000);
                _alLoadCache().cooldownUntil = 0;
                callback(null, data);
            } catch (e) { callback("AniList parse error: " + e); }
        } else if (xhr.status === 429) {
            var retryAfter = parseInt(xhr.getResponseHeader("Retry-After")) || 2;
            _alLoadCache().cooldownUntil = Math.floor(Date.now() / 1000) + retryAfter;
            var stale = _alGetStaleData(key);
            if (stale) callback(null, stale);
            else callback("AniList rate limited");
        } else if (xhr.status >= 500) {
            var stale2 = _alGetStaleData(key);
            if (stale2) callback(null, stale2);
            else callback("AniList server error: HTTP " + xhr.status);
        } else {
            var stale3 = _alGetStaleData(key);
            if (stale3) callback(null, stale3);
            else callback("AniList HTTP " + xhr.status);
        }
    };
    xhr.send(JSON.stringify({ query: query, variables: variables || {} }));
}

function _alEstimateAvailable(media) {
    var next = (media || {}).nextAiringEpisode || {};
    var nextEp = parseInt(next.episode) || 0;
    if (nextEp > 1) return nextEp - 1;
    return parseInt(media.episodes) || 0;
}

function _alSeasonObject(media) {
    var year = media.seasonYear;
    var quarter = _alTitleCaseSeason(media.season);
    if (!year && !quarter) return null;
    return { quarter: quarter, year: year };
}

function _alTitleCaseSeason(value) {
    var text = (value || "").trim();
    return text.charAt(0).toUpperCase() + text.slice(1).toLowerCase() || null;
}

function _alScoreValue(value) {
    try { return Math.round(parseFloat(value) / 10 * 100) / 100; }
    catch (e) { return null; }
}

function _alStatusLabel(value) {
    return (value || "").replace(/_/g, " ").replace(/\b\w/g, function(c) { return c.toUpperCase(); });
}

function _alAiringSummary(media) {
    var next = media.nextAiringEpisode || {};
    var nextEp = parseInt(next.episode) || 0;
    if (media.status === "RELEASING" && nextEp > 1) return "Episode " + (nextEp - 1) + " has aired";
    if (media.status === "RELEASING") return "Currently airing";
    return _alStatusLabel(media.status);
}

function _alNormaliseMedia(media) {
    var title = media.title || {};
    var available = _alEstimateAvailable(media);
    var malId = String(media.idMal || "");
    var refs = {};
    if (malId) refs.sync = { provider: "myanimelist", id: malId };
    return {
        id: String(media.id || ""),
        name: title.romaji || title.english || title.native || "",
        englishName: title.english || title.romaji || title.native || "",
        nativeName: title.native || "",
        thumbnail: (media.coverImage || {}).large || (media.coverImage || {}).medium || "",
        score: _alScoreValue(media.averageScore),
        type: media.format || "",
        episodeCount: media.episodes || "",
        availableEpisodes: { sub: available, dub: 0, raw: available },
        season: _alSeasonObject(media),
        status: media.status || "",
        statusLabel: _alStatusLabel(media.status),
        synonyms: media.synonyms || [],
        genres: media.genres || [],
        nextAiringEpisode: media.nextAiringEpisode || null,
        airingSummary: _alAiringSummary(media),
        startDate: media.startDate || null,
        providerRefs: refs
    };
}

function _alDecorateShow(media, streamProviderId) {
    var item = _alNormaliseMedia(media);
    streamProviderId = streamProviderId || "allanime";
    return MappingCache.decorateShow(item, "anilist", streamProviderId,
        MappingCache.getStreamShowId("anilist", item.id, streamProviderId));
}

function _alSearchRelevance(query, media) {
    var queryText = _cleanTitle(query);
    if (!queryText) return 0;
    var queryTokens = queryText.split(" ").filter(function(t) { return t; });
    var titleScores = [];
    var variants = _alMediaTitleVariants(media);
    for (var v = 0; v < variants.length; v++) {
        var candidate = _cleanTitle(variants[v]);
        if (!candidate) continue;
        var candidateTokens = candidate.split(" ").filter(function(t) { return t; });
        var ratio = _sequenceRatio(queryText, candidate);
        var containsPhrase = candidate.indexOf(queryText) !== -1;
        var exactMatch = queryText === candidate;
        var tokenHits = 0;
        for (var t = 0; t < queryTokens.length; t++) {
            if (candidateTokens.indexOf(queryTokens[t]) !== -1) tokenHits++;
        }
        var tokenCoverage = queryTokens.length > 0 ? tokenHits / queryTokens.length : 0;
        var startsWith = candidate.indexOf(queryText) === 0;
        var score = ratio * 45 + tokenCoverage * 35;
        if (exactMatch) score += 40;
        if (containsPhrase) score += 24;
        if (startsWith) score += 8;
        if (queryTokens.length === 1 && candidateTokens.indexOf(queryText) === -1 && !containsPhrase) score -= 20;
        titleScores.push(score);
    }
    return titleScores.length > 0 ? Math.max.apply(null, titleScores) : 0;
}

function _alMediaTitleVariants(media) {
    var title = media.title || {};
    var values = [title.english, title.romaji, title.native, media.englishName, media.name, media.nativeName];
    var synonyms = media.synonyms || [];
    for (var s = 0; s < Math.min(8, synonyms.length); s++) values.push(synonyms[s]);
    var seen = {}, variants = [];
    for (var i = 0; i < values.length; i++) {
        var text = (values[i] || "").trim();
        if (!text) continue;
        var key = _cleanTitle(text);
        if (!key || seen[key]) continue;
        seen[key] = true;
        variants.push(text);
    }
    return variants;
}

function _alFilterSearchResults(query, mediaList) {
    if (!(query || "").trim()) return mediaList;
    var ranked = [];
    for (var i = 0; i < mediaList.length; i++) {
        ranked.push({ score: _alSearchRelevance(query, mediaList[i]), media: mediaList[i] });
    }
    ranked.sort(function(a, b) { return b.score - a.score || (b.media.averageScore || 0) - (a.media.averageScore || 0); });
    var filtered = ranked.filter(function(item) { return item.score >= 45; });
    if (filtered.length === 0) filtered = ranked;
    return filtered.map(function(item) { return item.media; });
}

function _anilistListGenres(callback) {
    _alGql(_AL_Q_GENRES, {}, "genres", 86400, function(err, data) {
        if (err) { callback(err); return; }
        var genres = (data || {}).GenreCollection || [];
        callback(null, genres.filter(function(g) { return g; }));
    });
}

function _anilistPage(page, search, genre, sort, status, streamProviderId, callback) {
    var variables = { page: page || 1, perPage: 40, search: search || null, sort: sort || ["POPULARITY_DESC"] };
    var query = _AL_Q_PAGE_BASE;
    if (status === "RELEASING") query = _AL_Q_PAGE_RELEASING;
    else if (genre) { query = _AL_Q_PAGE_GENRE; variables.genre = genre; }
    _alGql(query, variables, "page", 600, function(err, data) {
        if (err) { callback(err); return; }
        var pageData = (data || {}).Page || {};
        var mediaList = pageData.media || [];
        var results = [];
        for (var i = 0; i < mediaList.length; i++) results.push(_alDecorateShow(mediaList[i], streamProviderId));
        callback(null, { results: results, hasNextPage: !!((pageData.pageInfo || {}).hasNextPage) });
    });
}

function _anilistPopular(page, mode, genre, streamProviderId, callback) {
    _anilistPage(page, null, genre || null, ["POPULARITY_DESC", "SCORE_DESC"], null, streamProviderId || "allanime", callback);
}

function _anilistRecent(page, mode, country, streamProviderId, callback) {
    _anilistPage(page, null, null, ["UPDATED_AT_DESC", "POPULARITY_DESC"], "RELEASING", streamProviderId || "allanime", callback);
}

function _anilistSearch(query, mode, page, genre, streamProviderId, callback) {
    var sort = (query || "").trim() ? ["SEARCH_MATCH", "POPULARITY_DESC", "SCORE_DESC"] : ["POPULARITY_DESC"];
    _anilistPage(page, query, genre || null, sort, null, streamProviderId || "allanime", function(err, result) {
        if (err) { callback(err); return; }
        var filtered = _alFilterSearchResults(query, result.results || []);
        callback(null, { results: filtered, hasNextPage: result.hasNextPage || false });
    });
}

function _anilistEpisodes(showId, mode, streamProviderId, callback) {
    var mediaId = parseInt(showId);
    if (isNaN(mediaId)) { callback("AniList metadata ids must be numeric, got: " + showId); return; }

    _alGql(_AL_Q_MEDIA, { id: mediaId }, "media-detail", 21600, function(err, data) {
        if (err) { callback(err); return; }
        var media = (data || {}).Media || {};
        if (!media) { callback("No AniList media found for id " + showId); return; }

        var base = _alDecorateShow(media, streamProviderId || "allanime");
        _alBuildSeasonEntries(media, streamProviderId || "allanime", function(seasonEntries) {
            var relations = [];
            var edges = ((media.relations || {}).edges) || [];
            var nodes = ((media.relations || {}).nodes) || [];
            for (var r = 0; r < edges.length; r++) {
                var node = nodes[r] || {};
                var edge = edges[r] || {};
                var t = node.title || {};
                relations.push({
                    id: String(node.id || ""), relationType: edge.relationType || "",
                    name: t.romaji || t.english || t.native || "",
                    englishName: t.english || t.romaji || t.native || "",
                    nativeName: t.native || "",
                    status: node.status || "", type: node.format || "",
                    season: (node.season || node.seasonYear) ? { quarter: _alTitleCaseSeason(node.season), year: node.seasonYear } : null
                });
            }

            var mapping = { status: "unmapped", streamId: "", confidence: 0, reason: "" };
            var episodes = [];
            var mappingError = "";

            if ((streamProviderId || "allanime") === "allanime") {
                _anilistAllAnimeMapResolve(media, mode, function(mapErr, mapResult) {
                    mapResult = mapResult || {};
                    if (!mapErr && mapResult.status === "mapped" && mapResult.streamId) {
                        _allanimeEpisodes(mapResult.streamId, mode, "allanime", function(epErr, epData) {
                            var payload = _alBuildEpisodesPayload(media, base, seasonEntries, relations,
                                mapResult, epErr ? [] : (epData || {}).episodes || [], mappingError, streamProviderId);
                            callback(epErr, payload);
                        });
                    } else {
                        mappingError = (mapResult || {}).reason || "No reliable AllAnime mapping is available for playback yet.";
                        var payload2 = _alBuildEpisodesPayload(media, base, seasonEntries, relations,
                            mapResult || mapping, [], mappingError, streamProviderId);
                        callback(null, payload2);
                    }
                });
            } else {
                var payload3 = _alBuildEpisodesPayload(media, base, seasonEntries, relations,
                    mapping, [], "", streamProviderId);
                callback(null, payload3);
            }
        });
    });
}

function _alBuildEpisodesPayload(media, base, seasonEntries, relations, mapping, episodes, mappingError, streamProviderId) {
    var payload = JSON.parse(JSON.stringify(base));
    payload.description = _alCleanDescription(media.description);
    payload.bannerImage = media.bannerImage || "";
    payload.genres = media.genres || [];
    payload.duration = media.duration || null;
    payload.seasonEntries = seasonEntries;
    payload.relations = relations;
    payload.nextAiringEpisode = media.nextAiringEpisode || null;
    payload.episodes = episodes;
    var decorated = MappingCache.decorateShow(
        { id: base.id, providerRefs: base.providerRefs || {} },
        "anilist", streamProviderId || "allanime", mapping.streamId || ""
    );
    payload.providerRefs = decorated.providerRefs || base.providerRefs || {};
    payload.mappingStatus = mapping;
    if (mappingError) payload.mappingError = mappingError;
    return payload;
}

function _alCleanDescription(value) {
    var text = (value || "").replace(/<br\s*\/?>/gi, "\n").replace(/<[^>]+>/g, " ");
    text = text.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
    text = text.replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&nbsp;/g, " ");
    return text.replace(/\s+/g, " ").trim();
}

function _alBuildSeasonEntries(media, streamProviderId, callback) {
    var currentId = String(media.id || "");
    if (!currentId) { callback([]); return; }

    var entries = {};
    entries[currentId] = Object.assign(_alSeasonEntryFromMedia(media, "CURRENT"), { isCurrent: true });
    var visited = {};
    visited[currentId] = true;
    var pending = [];

    var edges = ((media.relations || {}).edges) || [];
    var nodes = ((media.relations || {}).nodes) || [];
    for (var i = 0; i < edges.length; i++) {
        if (_alIsSeasonRelation(edges[i], nodes[i])) {
            pending.push([String(nodes[i].id || ""), String((edges[i] || {}).relationType || "").toUpperCase()]);
        }
    }

    function processPending() {
        if (pending.length === 0 || Object.keys(entries).length >= 12) {
            var ordered = [];
            var keys = Object.keys(entries);
            keys.sort(function(a, b) { return _alSeasonSortKey(entries[a]) - _alSeasonSortKey(entries[b]); });
            for (var k = 0; k < keys.length; k++) {
                var entry = entries[keys[k]];
                ordered.push(MappingCache.decorateShow(entry, "anilist", streamProviderId,
                    MappingCache.getStreamShowId("anilist", entry.id || "", streamProviderId)));
            }
            callback(ordered);
            return;
        }
        var item = pending.shift();
        var relationId = item[0], relationType = item[1];
        if (!relationId || visited[relationId]) { processPending(); return; }
        visited[relationId] = true;

        var relId = parseInt(relationId);
        if (isNaN(relId)) { processPending(); return; }
        _alGql(_AL_Q_RELATION_STEP, { id: relId }, "relation-step", 21600, function(err, data) {
            if (!err) {
                var relMedia = (data || {}).Media || {};
                if (relMedia) {
                    var entry = _alSeasonEntryFromMedia(relMedia, relationType);
                    if (entry.id) {
                        entry.isCurrent = entry.id === currentId;
                        entries[entry.id] = entry;
                        var nextEdges = ((relMedia.relations || {}).edges) || [];
                        var nextNodes = ((relMedia.relations || {}).nodes) || [];
                        for (var n = 0; n < nextEdges.length; n++) {
                            if (_alIsSeasonRelation(nextEdges[n], nextNodes[n])) {
                                var nextId = String(nextNodes[n].id || "");
                                if (nextId && !visited[nextId])
                                    pending.push([nextId, String((nextEdges[n] || {}).relationType || "").toUpperCase()]);
                            }
                        }
                    }
                }
            }
            processPending();
        });
    }
    processPending();
}

function _alSeasonEntryFromMedia(media, relationType) {
    var title = media.title || {};
    var malId = String(media.idMal || "");
    var item = {
        id: String(media.id || ""), relationType: relationType || "",
        name: title.romaji || title.english || title.native || "",
        englishName: title.english || title.romaji || title.native || "",
        nativeName: title.native || "",
        status: media.status || "", type: media.format || "",
        season: _alSeasonObject(media),
        thumbnail: (media.coverImage || {}).large || (media.coverImage || {}).medium || ""
    };
    var refs = { metadata: { provider: "anilist", id: item.id } };
    if (malId) refs.sync = { provider: "myanimelist", id: malId };
    item.providerRefs = refs;
    return item;
}

function _alIsSeasonRelation(edge, node) {
    var relType = String((edge || {}).relationType || "").toUpperCase();
    if (!_AL_SEASON_RELATION_TYPES[relType]) return false;
    var nodeId = String((node || {}).id || "").trim();
    if (!nodeId) return false;
    var nodeFormat = String((node || {}).format || "").toUpperCase();
    if (nodeFormat && !_AL_SEASON_FORMATS[nodeFormat]) return false;
    return true;
}

function _alSeasonSortKey(entry) {
    var season = entry.season || {};
    var yearValue = parseInt(season.year) || 0;
    var quarter = String(season.quarter || "").toUpperCase();
    return (yearValue > 0 ? 0 : 1) * 100000 + (yearValue || 9999) * 100 + (_AL_SEASON_ORDER[quarter] || 99);
}

function _anilistFeed(libraryEntries, mode, streamProviderId, callback) {
    var contextsByMediaId = {};
    var orderedMediaIds = [];
    var entries = libraryEntries || [];
    streamProviderId = streamProviderId || "allanime";

    for (var e = 0; e < entries.length; e++) {
        var context = _alEntryFeedContext(entries[e], streamProviderId);
        if (!context) continue;
        var mediaId = (context.mediaId || "").trim();
        if (!mediaId) continue;
        if (!contextsByMediaId[mediaId]) contextsByMediaId[mediaId] = [];
        contextsByMediaId[mediaId].push(context);
        if (orderedMediaIds.indexOf(mediaId) === -1) orderedMediaIds.push(mediaId);
    }

    if (!orderedMediaIds.length) { callback(null, { results: [] }); return; }

    var mediaLookup = {};
    var batchIndex = 0;

    function nextBatch() {
        if (batchIndex >= orderedMediaIds.length) {
            _alBuildFeedResults(contextsByMediaId, orderedMediaIds, mediaLookup, streamProviderId, callback);
            return;
        }
        var chunk = orderedMediaIds.slice(batchIndex, batchIndex + 50);
        batchIndex += 50;
        var ids = [];
        for (var i = 0; i < chunk.length; i++) ids.push(parseInt(chunk[i]));
        _alGql(_AL_Q_FEED_BATCH, { ids: ids }, "feed-batch", 300, function(err, data) {
            if (!err) {
                var mediaList = ((data || {}).Page || {}).media || [];
                for (var m = 0; m < mediaList.length; m++) {
                    mediaLookup[String(mediaList[m].id || "")] = mediaList[m];
                }
            }
            nextBatch();
        });
    }
    nextBatch();
}

function _alEntryFeedContext(entry, streamProviderId) {
    var refs = entry.providerRefs || {};
    var metadataRef = refs.metadata || {};
    var provider = (metadataRef.provider || "").trim() || "allanime";
    var metadataId = (metadataRef.id || entry.id || "").trim();
    var streamRef = _alLibraryStreamRef(entry);

    if (provider === "anilist" && metadataId) {
        return { libraryId: String(entry.id || metadataId), mediaId: metadataId, entry: entry, streamRef: streamRef };
    }
    if (provider !== "allanime") return null;

    var mappedMediaId = "";
    if (metadataId) {
        mappedMediaId = MappingCache.getProviderShowId("allanime", metadataId, "anilist");
        if (!mappedMediaId)
            mappedMediaId = MappingCache.getSourceShowId("anilist", streamRef.provider || "allanime", streamRef.id || metadataId);
        if (mappedMediaId)
            MappingCache.rememberProviderMapping("allanime", metadataId, "anilist", mappedMediaId,
                { status: "mapped", confidence: 1, reason: "Derived from existing AniList to AllAnime mapping." });
    }
    if (!mappedMediaId) return null;

    if (streamRef.provider && streamRef.id)
        MappingCache.rememberProviderMapping("anilist", mappedMediaId, streamRef.provider, streamRef.id,
            { status: "mapped", confidence: 1, reason: "Derived from cached legacy library entry." });

    return { libraryId: String(entry.id || ""), mediaId: mappedMediaId, entry: entry, streamRef: streamRef };
}

function _alLibraryStreamRef(entry) {
    var refs = entry.providerRefs || {};
    var streamRef = refs.stream || {};
    if (streamRef.provider && streamRef.id) return { provider: String(streamRef.provider), id: String(streamRef.id) };
    var metadataRef = refs.metadata || {};
    var metadataProvider = (metadataRef.provider || "").trim();
    var metadataId = (metadataRef.id || "").trim();
    if (metadataProvider === "allanime" && metadataId) return { provider: "allanime", id: metadataId };
    var entryId = (entry.id || "").trim();
    if (!metadataProvider && entryId) return { provider: "allanime", id: entryId };
    return {};
}

function _alBuildFeedResults(contextsByMediaId, orderedMediaIds, mediaLookup, streamProviderId, callback) {
    var alerts = [], upcoming = [], followedMediaIds = {};
    var nowTs = Math.floor(Date.now() / 1000);

    for (var m = 0; m < orderedMediaIds.length; m++) {
        var mediaId = orderedMediaIds[m];
        var media = mediaLookup[mediaId];
        if (!media || media.status !== "RELEASING") continue;
        var nextAiring = media.nextAiringEpisode || {};
        var nextEpisode = parseInt(nextAiring.episode) || 0;
        var latestReleased = nextEpisode > 1 ? nextEpisode - 1 : 0;
        if (latestReleased <= 0) continue;
        var airingAt = parseInt(nextAiring.airingAt) || 0;
        var timeUntil = parseInt(nextAiring.timeUntilAiring) || 0;
        var baseShow = _alDecorateShow(media, streamProviderId);

        var contexts = contextsByMediaId[mediaId] || [];
        for (var c = 0; c < contexts.length; c++) {
            var context = contexts[c];
            var entry = context.entry || {};
            var tracking = _alFeedTrackingState(entry, latestReleased, nextEpisode);
            if (!tracking.eligible) continue;
            var lastWatched = parseInt(tracking.lastWatched) || 0;
            followedMediaIds[mediaId] = true;
            var newCount = Math.max(0, latestReleased - lastWatched);

            var showPayload = JSON.parse(JSON.stringify(baseShow));
            showPayload.id = context.libraryId || baseShow.id || mediaId;
            showPayload.providerRefs = JSON.parse(JSON.stringify(baseShow.providerRefs || {}));
            showPayload.providerRefs.metadata = { provider: "anilist", id: mediaId };
            var sRef = context.streamRef || {};
            if (sRef.provider && sRef.id) showPayload.providerRefs.stream = { provider: sRef.provider, id: sRef.id };

            var item = JSON.parse(JSON.stringify(showPayload));
            item.mediaId = mediaId;
            item.title = showPayload.englishName || showPayload.name || entry.englishName || entry.name || "";
            item.poster = showPayload.thumbnail || entry.thumbnail || "";
            item.nextEpisode = String(lastWatched + 1);
            item.watchedThrough = String(lastWatched);
            item.newCount = newCount;
            item.watchGap = tracking.releaseGap || 0;
            item.nextGap = tracking.nextGap || 0;
            item.nearCurrent = (tracking.releaseGap || 0) <= 1;
            item.trackingStatus = tracking.status || "";
            item.latestReleasedEpisode = String(latestReleased);
            item.status = media.status || "";
            item.statusLabel = _alStatusLabel(media.status);
            item.releaseText = _alReleaseText(latestReleased, nextEpisode, airingAt, nowTs);
            item.airingAt = airingAt || null;
            item.timeUntilAiring = (airingAt && airingAt > nowTs) ? timeUntil : null;
            item.followMode = tracking.followMode || "auto";
            item.feedReason = _alFeedReasonText(tracking.releaseGap || 0, tracking.followMode);

            if (newCount > 0) {
                item.feedKind = "release";
                item.eventEpisode = String(latestReleased);
                item.eventKey = "episode_release:" + mediaId + ":" + latestReleased;
                alerts.push(item);
            } else if (tracking.upcomingEligible && airingAt && airingAt > nowTs && nextEpisode > lastWatched) {
                item.feedKind = "upcoming";
                upcoming.push(item);
            }
        }
    }

    alerts.sort(function(a, b) { return (a.watchGap || 0) - (b.watchGap || 0) || (a.timeUntilAiring || 0) - (b.timeUntilAiring || 0) || (a.title || "").localeCompare(b.title || ""); });
    upcoming.sort(function(a, b) { return (a.timeUntilAiring || 0) - (b.timeUntilAiring || 0) || (a.title || "").localeCompare(b.title || ""); });
    callback(null, {
        results: alerts, upcoming: upcoming,
        summary: { alerts: alerts.length, upcoming: upcoming.length, following: Object.keys(followedMediaIds).length }
    });
}

function _alFeedTrackingState(entry, latestReleased, nextEpisode) {
    var lastWatched = 0;
    try { lastWatched = parseInt(parseFloat(entry.lastWatchedEpNum || "0")); } catch (e) {}
    var followMode = (entry.feedFollowMode || "auto").trim().toLowerCase();
    if (followMode !== "following" && followMode !== "muted") followMode = "auto";
    var status = _alEntryListStatus(entry);

    if (lastWatched <= 0) {
        return { eligible: false, status: status, followMode: followMode, lastWatched: lastWatched,
            releaseGap: Math.max(0, latestReleased - lastWatched), nextGap: Math.max(0, nextEpisode - lastWatched), upcomingEligible: false };
    }
    var releaseGap = Math.max(0, latestReleased - lastWatched);
    var nextGap = Math.max(0, nextEpisode - lastWatched);
    if (followMode === "muted")
        return { eligible: false, status: status, followMode: followMode, lastWatched: lastWatched,
            releaseGap: releaseGap, nextGap: nextGap, upcomingEligible: false };
    var manuallyFollowing = followMode === "following";
    var automaticallyFollowing = status === "watching" && releaseGap <= 2;
    var eligible = manuallyFollowing || automaticallyFollowing;
    var upcomingEligible = (manuallyFollowing && nextGap <= 1) || (status === "watching" && releaseGap === 0 && nextGap === 1);
    return { eligible: eligible, status: status, followMode: followMode, lastWatched: lastWatched,
        releaseGap: releaseGap, nextGap: nextGap, upcomingEligible: upcomingEligible };
}

function _alEntryListStatus(entry) {
    var value = (entry.listStatus || "").trim().toLowerCase();
    if (["watching", "completed", "on_hold", "dropped", "plan_to_watch"].indexOf(value) !== -1) return value;
    return "plan_to_watch";
}

function _alReleaseText(latestReleased, nextEpisode, airingAt, nowTs) {
    if (latestReleased <= 0) return "Currently airing";
    if (airingAt && airingAt > nowTs && nextEpisode > latestReleased)
        return "Episode " + latestReleased + " aired; episode " + nextEpisode + " is scheduled next.";
    return "Episode " + latestReleased + " aired recently.";
}

function _alFeedReasonText(releaseGap, followMode) {
    if (followMode === "following") return "Pinned to Feed";
    if (releaseGap <= 0) return "Caught up";
    if (releaseGap === 1) return "One behind";
    return "Near current";
}
