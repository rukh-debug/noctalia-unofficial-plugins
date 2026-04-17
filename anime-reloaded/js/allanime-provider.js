var _AA_API = "https://api.allanime.day/api";
var _AA_REFERER = "https://allmanga.to";
var _AA_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0";
var _AA_BASE = "allanime.day";

var _AA_Q_SHOWS = "query($search:SearchInput $limit:Int $page:Int $translationType:VaildTranslationTypeEnumType $countryOrigin:VaildCountryOriginEnumType){shows(search:$search limit:$limit page:$page translationType:$translationType countryOrigin:$countryOrigin){edges{_id name englishName nativeName thumbnail score type season availableEpisodes}}}";
var _AA_Q_EPISODES = "query($showId:String!){show(_id:$showId){_id name englishName description thumbnail availableEpisodesDetail lastEpisodeDate status}}";
var _AA_Q_STREAM = "query($showId:String! $translationType:VaildTranslationTypeEnumType! $episodeString:String!){episode(showId:$showId translationType:$translationType episodeString:$episodeString){episodeString sourceUrls}}";

var _AA_GENRES = ["Action","Adventure","Comedy","Drama","Ecchi","Fantasy","Horror","Mahou Shoujo","Mecha","Music","Mystery","Psychological","Romance","Sci-Fi","Slice of Life","Sports","Supernatural","Thriller"];

var _AA_PROVIDER_PRIORITY = {
    "auto": ["Default","S-mp4","Luf-Mp4","Yt-mp4"],
    "default": ["Default","S-mp4","Luf-Mp4","Yt-mp4"],
    "sharepoint": ["S-mp4","Default","Luf-Mp4","Yt-mp4"],
    "hianime": ["Luf-Mp4","Default","S-mp4","Yt-mp4"],
    "youtube": ["Yt-mp4","Default","S-mp4","Luf-Mp4"]
};

var _AA_HEX = {
    "79":"A","7a":"B","7b":"C","7c":"D","7d":"E","7e":"F","7f":"G","70":"H",
    "71":"I","72":"J","73":"K","74":"L","75":"M","76":"N","77":"O","68":"P",
    "69":"Q","6a":"R","6b":"S","6c":"T","6d":"U","6e":"V","6f":"W","60":"X",
    "61":"Y","62":"Z","59":"a","5a":"b","5b":"c","5c":"d","5d":"e","5e":"f",
    "5f":"g","50":"h","51":"i","52":"j","53":"k","54":"l","55":"m","56":"n",
    "57":"o","48":"p","49":"q","4a":"r","4b":"s","4c":"t","4d":"u","4e":"v",
    "4f":"w","40":"x","41":"y","42":"z","08":"0","09":"1","0a":"2","0b":"3",
    "0c":"4","0d":"5","0e":"6","0f":"7","00":"8","01":"9","15":"-","16":".",
    "67":"_","46":"~","02":":","17":"/","07":"?","1b":"#","63":"[","65":"]",
    "78":"@","19":"!","1c":"$","1e":"&","10":"(","11":")","12":"*","13":"+",
    "14":",","03":";","05":"=","1d":"%"
};

function _aaDecodeUrl(encoded) {
    var pairs = [];
    for (var i = 0; i < encoded.length; i += 2) pairs.push(encoded.substring(i, i + 2));
    var result = "";
    for (var j = 0; j < pairs.length; j++) result += _AA_HEX[pairs[j]] || pairs[j];
    return result.replace("/clock", "/clock.json");
}

function _aaDecodeTobeparsed(payload) {
    var text = (payload || "").trim();
    if (!text) return null;
    try {
        var raw = CryptoHelper.base64Decode(text);
        // Key = SHA-256("SimtVuagFbGR2K7P") = SHA-256(reverse("P7K2RGbFgauVtmiS"))
        var key = CryptoHelper.hexToBytes("cb156d973b237c31a2aa2dbac52dc963da6a2e571968bb69df00242f80c46348");
        var decrypted = CryptoHelper.aesGcmDecrypt(key, raw);
        return JSON.parse(CryptoHelper.bytesToString(decrypted));
    } catch (e) {
        console.log("[AA] tobeparsed error: " + e);
        return null;
    }
}

function _aaGql(variables, query, callback) {
    var xhr = new XMLHttpRequest();
    xhr.open("POST", _AA_API, true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("Referer", _AA_REFERER);
    xhr.setRequestHeader("User-Agent", _AA_AGENT);
    xhr.timeout = 15000;

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) return;
        if (xhr.status < 200 || xhr.status >= 300) {
            callback("AllAnime HTTP " + xhr.status + ": " + xhr.statusText);
            return;
        }
        try {
            var parsed = JSON.parse(xhr.responseText);
            var data = parsed.data;
            var hadTobeparsed = typeof data === "object" && typeof data.tobeparsed === "string";
            if (hadTobeparsed) {
                console.log("[AA] tobeparsed found, raw length: " + data.tobeparsed.length);
                var decoded = _aaDecodeTobeparsed(data.tobeparsed);
                if (decoded !== null) {
                    console.log("[AA] tobeparsed decoded OK, keys: " + JSON.stringify(Object.keys(decoded)));
                    console.log("[AA] tobeparsed content: " + JSON.stringify(decoded).substring(0, 500));
                    parsed.data = decoded;
                } else {
                    console.log("[AA] tobeparsed decode FAILED, raw length: " + data.tobeparsed.length);
                }
            }
            callback(null, parsed);
        } catch (e) {
            callback("AllAnime parse error: " + e);
        }
    };
    xhr.send(JSON.stringify({ variables: variables, query: query }));
}

function _aaFetch(url, callback) {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", url, true);
    xhr.setRequestHeader("Referer", _AA_REFERER);
    xhr.setRequestHeader("User-Agent", _AA_AGENT);
    xhr.timeout = 15000;
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) return;
        if (xhr.status < 200 || xhr.status >= 300) {
            callback("AllAnime fetch HTTP " + xhr.status);
            return;
        }
        callback(null, xhr.responseText);
    };
    xhr.send();
}

function _aaNormalise(edge) {
    var thumb = edge.thumbnail || "";
    var avail = edge.availableEpisodes || {};
    return {
        id: edge._id || "",
        name: edge.name || "",
        englishName: edge.englishName || edge.name || "",
        nativeName: edge.nativeName || "",
        thumbnail: thumb,
        score: edge.score,
        type: edge.type || "",
        availableEpisodes: { sub: avail.sub || 0, dub: avail.dub || 0, raw: avail.raw || 0 },
        season: edge.season
    };
}

function _aaFormatEpisodeNumber(value) {
    var text = (value || "").trim();
    if (!text) return "";
    var match = text.match(/\d+(?:\.\d+)?/);
    if (!match) return text;
    var num = parseFloat(match[0]);
    if (isNaN(num)) return text;
    if (num === Math.floor(num)) return String(Math.floor(num));
    return String(num).replace(/0+$/, "").replace(/\.$/, "");
}

function _aaParseEpisodeNumber(value) {
    var text = (value || "").trim();
    if (!text) return null;
    var match = text.match(/\d+(?:\.\d+)?/);
    if (!match) return null;
    var num = parseFloat(match[0]);
    return isNaN(num) ? null : num;
}

function _aaEpisodeSortKey(value) {
    var num = _aaParseEpisodeNumber(value);
    return num === null ? -1 : num;
}

function _allanimeListGenres() { return _AA_GENRES.slice(); }

function _allanimeDecorateShow(show, streamProviderId) {
    streamProviderId = streamProviderId || "allanime";
    return MappingCache.decorateShow(show, "allanime", streamProviderId, show.id || "");
}

function _allanimeShows(searchObj, page, mode, country, streamProviderId, callback) {
    _aaGql({
        search: searchObj, limit: 40, page: page,
        translationType: mode, countryOrigin: country || "ALL"
    }, _AA_Q_SHOWS, function(err, data) {
        if (err) { callback(err); return; }
        var edges = (((data || {}).data || {}).shows || {}).edges || [];
        var results = [];
        for (var i = 0; i < edges.length; i++) {
            results.push(_allanimeDecorateShow(_aaNormalise(edges[i]), streamProviderId));
        }
        callback(null, { results: results, hasNextPage: results.length === 40 });
    });
}

function _allanimeShowsWithFallbacks(searchVariants, page, mode, country, streamProviderId, callback) {
    var index = 0;
    function tryNext() {
        if (index >= searchVariants.length) {
            callback("No working feed query variant found");
            return;
        }
        var variant = searchVariants[index];
        index++;
        _allanimeShows(variant, page, mode, country, streamProviderId, function(err, data) {
            if (err) {
                var isRetryable = err.indexOf("HTTP 400") !== -1 || err.indexOf("HTTP 500") !== -1;
                if (isRetryable && index < searchVariants.length) { tryNext(); return; }
                callback(err);
                return;
            }
            callback(null, data);
        });
    }
    tryNext();
}

function _allanimePopular(page, mode, genre, streamProviderId, callback) {
    var search = { allowAdult: false, allowUnknown: false };
    if (genre) search.genres = [genre];
    _allanimeShowsWithFallbacks([
        Object.assign({}, search, { sortBy: "Top" }),
        Object.assign({}, search, { sortBy: "Popular" }),
        Object.assign({}, search, { sortBy: "Trending" }),
        search
    ], page, mode, "ALL", streamProviderId || "allanime", callback);
}

function _allanimeRecent(page, mode, country, streamProviderId, callback) {
    var search = { allowAdult: false, allowUnknown: false };
    _allanimeShowsWithFallbacks([
        Object.assign({}, search, { sortBy: "Recent" }),
        Object.assign({}, search, { sortBy: "Latest_Update" }),
        Object.assign({}, search, { sortBy: "Trending" }),
        search
    ], page, mode, country || "ALL", streamProviderId || "allanime", callback);
}

function _allanimeSearchShows(query, mode, page, streamProviderId, callback) {
    var search = { allowAdult: false, allowUnknown: false, query: query };
    _allanimeShows(search, page || 1, mode, "ALL", streamProviderId || "allanime", callback);
}

function _allanimeEpisodes(showId, mode, streamProviderId, callback) {
    _aaGql({ showId: showId }, _AA_Q_EPISODES, function(err, data) {
        if (err) { callback(err); return; }
        var show = ((data || {}).data || {}).show || {};
        var detail = show.availableEpisodesDetail || {};
        var episodes = [];
        var epList = detail[mode] || [];
        for (var i = 0; i < epList.length; i++) {
            episodes.push({ id: showId + "-episode-" + epList[i], number: epList[i] });
        }
        var desc = show.description || "";
        desc = desc.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
        var payload = {
            episodes: episodes, episodeDetail: detail,
            description: desc, thumbnail: show.thumbnail || ""
        };
        streamProviderId = streamProviderId || "allanime";
        var decorated = MappingCache.decorateShow({ id: showId }, "allanime", streamProviderId, showId);
        if (decorated.providerRefs) payload.providerRefs = decorated.providerRefs;
        callback(null, payload);
    });
}

function _allanimeFeed(libraryEntries, mode, callback) {
    var episodeMap = {};
    var entries = libraryEntries || [];
    var index = 0;

    function processNext() {
        if (index >= entries.length) {
            callback(null, { results: _aaBuildFeedItems(entries, episodeMap) });
            return;
        }
        var entry = entries[index];
        index++;
        var showId = entry.id || "";
        if (!showId) { processNext(); return; }
        MappingCache.rememberShowMapping("allanime", showId, "allanime", showId);
        _aaGql({ showId: showId }, _AA_Q_EPISODES, function(err, data) {
            if (!err) {
                var show = ((data || {}).data || {}).show || {};
                var detail = show.availableEpisodesDetail || {};
                var eps = [];
                var epList = detail[mode] || [];
                var cleaned = [];
                for (var i = 0; i < epList.length; i++) {
                    var fmt = _aaFormatEpisodeNumber(epList[i]);
                    if (fmt) cleaned.push(fmt);
                }
                cleaned.sort(function(a, b) { return _aaEpisodeSortKey(a) - _aaEpisodeSortKey(b); });
                var unique = [];
                var seen = {};
                for (var j = 0; j < cleaned.length; j++) {
                    if (!seen[cleaned[j]]) { seen[cleaned[j]] = true; unique.push(cleaned[j]); }
                }
                episodeMap[showId] = {
                    episodes: unique,
                    thumbnail: show.thumbnail || entry.thumbnail || "",
                    lastEpisodeDate: _aaExtractLastEpisodeDate(show, mode)
                };
            }
            processNext();
        });
    }
    processNext();
}

function _aaExtractLastEpisodeDate(show, mode) {
    var detail = (show || {}).lastEpisodeDate || {};
    var modeValue = detail[mode] || {};
    if (typeof modeValue !== "object") return "";
    var year = modeValue.year, month = modeValue.month, day = modeValue.date;
    var hour = modeValue.hour || 0, minute = modeValue.minute || 0;
    if (!year || !month || !day) return "";
    return year + "-" + String(month).padStart(2, "0") + "-" + String(day).padStart(2, "0") +
        "T" + String(hour).padStart(2, "0") + ":" + String(minute).padStart(2, "0") + ":00+00:00";
}

function _aaBuildFeedItems(libraryEntries, episodeMap) {
    var items = [];
    var entries = libraryEntries || [];
    var now = Date.now() / 1000;
    for (var e = 0; e < entries.length; e++) {
        var entry = entries[e];
        var showId = entry.id || "";
        if (!showId) continue;
        var lastWatched = _aaParseEpisodeNumber(entry.lastWatchedEpNum);
        if (lastWatched === null || lastWatched <= 0) continue;
        var epData = episodeMap[showId] || {};
        var episodeNumbers = (epData.episodes || []).slice().sort(function(a, b) { return _aaEpisodeSortKey(a) - _aaEpisodeSortKey(b); });
        if (!episodeNumbers.length) continue;
        var lastEpDate = epData.lastEpisodeDate || "";
        if (!_aaIsRecentEnough(lastEpDate)) continue;
        var latestAvailable = _aaParseEpisodeNumber(episodeNumbers[episodeNumbers.length - 1]);
        if (latestAvailable === null || latestAvailable <= lastWatched) continue;
        var gap = latestAvailable - lastWatched;
        if (gap <= 0 || gap > 3) continue;
        if (!_aaHasConsistentHistory(entry, episodeNumbers)) continue;
        var newEps = [];
        for (var n = 0; n < episodeNumbers.length; n++) {
            var parsed = _aaParseEpisodeNumber(episodeNumbers[n]);
            if (parsed !== null && parsed > lastWatched) newEps.push(episodeNumbers[n]);
        }
        if (!newEps.length) continue;
        var title = entry.englishName || entry.name || "";
        var poster = entry.thumbnail || epData.thumbnail || "";
        items.push({
            id: showId, title: title, poster: poster,
            nextEpisode: _aaFormatEpisodeNumber(newEps[0]),
            newCount: newEps.length, _sortGap: gap, _sortLatest: latestAvailable
        });
    }
    items.sort(function(a, b) { return a._sortGap - b._sortGap || b._sortLatest - a._sortLatest || a.title.localeCompare(b.title); });
    for (var i = 0; i < items.length; i++) { delete items[i]._sortGap; delete items[i]._sortLatest; }
    return items;
}

function _aaIsRecentEnough(lastEpisodeDate, days) {
    if (!lastEpisodeDate) return false;
    days = days || 90;
    try {
        var d = new Date(lastEpisodeDate);
        if (isNaN(d.getTime())) return false;
        var cutoff = Date.now() - days * 86400000;
        return d.getTime() >= cutoff;
    } catch (e) { return false; }
}

function _aaHasConsistentHistory(entry, episodeNumbers) {
    var watchedSet = {};
    var watchedEpisodes = entry.watchedEpisodes || [];
    for (var w = 0; w < watchedEpisodes.length; w++) {
        var fmt = _aaFormatEpisodeNumber(watchedEpisodes[w]);
        if (fmt) watchedSet[fmt] = true;
    }
    var lastWatched = _aaParseEpisodeNumber(entry.lastWatchedEpNum);
    if (lastWatched === null || lastWatched <= 0) return false;
    var start = Math.max(1, Math.floor(lastWatched) - 4);
    var end = Math.floor(lastWatched);
    var availableSet = {};
    for (var a = 0; a < episodeNumbers.length; a++) availableSet[_aaFormatEpisodeNumber(episodeNumbers[a])] = true;
    for (var c = start; c <= end; c++) {
        var label = String(c);
        if (!availableSet[label] || !watchedSet[label]) return false;
    }
    return true;
}

function _allanimeResolveStream(showId, epNum, mode, mirrorPref, qualityPref, metadataProviderId, callback, title) {
    metadataProviderId = metadataProviderId || "allanime";
    var resolvedShowId = String(showId || "");
    var mapped = MappingCache.getStreamShowId(metadataProviderId, showId, "allanime");
    if (mapped) resolvedShowId = mapped;

    // If same provider (e.g. browsing AllAnime directly), no mapping needed
    if (metadataProviderId === "allanime") {
        resolvedShowId = String(showId || "");
    }

    // No mapping and different metadata provider — dynamically resolve via title search
    if (!mapped && metadataProviderId !== "allanime" && title) {
        console.log("[AA] no cached mapping for " + metadataProviderId + ":" + showId + ", searching by title: " + title);
        _allanimeSearchShows(title, mode, 1, "allanime", function(err, data) {
            if (err || !data || !data.results || !data.results.length) {
                callback(null, { error: "No AllAnime mapping found for \"" + title + "\".",
                    code: "no_provider_mapping", providerFailures: [] });
                return;
            }
            var best = data.results[0];
            resolvedShowId = String(best.id || "");
            console.log("[AA] mapped to allanime:" + resolvedShowId + " (" + (best.name || best.englishName || "") + ")");
            MappingCache.rememberShowMapping(metadataProviderId, showId, "allanime", resolvedShowId);
            _doResolveStream(resolvedShowId, epNum, mode, mirrorPref, qualityPref, metadataProviderId, showId, callback);
        });
        return;
    }

    if (!resolvedShowId) {
        callback(null, { error: "No cached show mapping exists from " + metadataProviderId + " to allanime.",
            code: "missing_provider_mapping", providerFailures: [] });
        return;
    }

    _doResolveStream(resolvedShowId, epNum, mode, mirrorPref, qualityPref, metadataProviderId, showId, callback);
}

function _doResolveStream(resolvedShowId, epNum, mode, mirrorPref, qualityPref, metadataProviderId, requestedShowId, callback) {
    console.log("[AA] resolveStream: showId=" + resolvedShowId + " ep=" + epNum + " mode=" + mode);
    _aaGql({ showId: resolvedShowId, translationType: mode, episodeString: String(epNum) }, _AA_Q_STREAM, function(err, data) {
        if (err) { callback(err); return; }
        var episode = ((data || {}).data || {}).episode || {};
        var sourceUrls = episode.sourceUrls || [];
        console.log("[AA] stream response: episode=" + JSON.stringify(episode).substring(0, 200) + " sourceUrls=" + sourceUrls.length);
        if (!sourceUrls.length) {
            callback(null, { error: "This episode did not return any stream sources.",
                code: "no_sources", providerFailures: [] });
            return;
        }
        var sources = {};
        for (var s = 0; s < sourceUrls.length; s++) {
            var name = sourceUrls[s].sourceName || "";
            var url = sourceUrls[s].sourceUrl || "";
            if (name && url) sources[name] = url;
        }

        _aaGql({ showId: resolvedShowId }, _AA_Q_EPISODES, function(err2, data2) {
            var show = ((data2 || {}).data || {}).show || {};
            var title = show.englishName || show.name || "Unknown";
            var metadata = {
                title: title, episode: String(epNum), showId: resolvedShowId,
                requestedShowId: requestedShowId, metadataProvider: metadataProviderId, streamProvider: "allanime"
            };
            MappingCache.rememberShowMapping(metadataProviderId, requestedShowId, "allanime", resolvedShowId);

            var priority = _AA_PROVIDER_PRIORITY[mirrorPref] || _AA_PROVIDER_PRIORITY["auto"];
            var providerFailures = [];

            function tryProvider(idx) {
                if (idx >= priority.length) {
                    callback(null, { error: _aaSummariseFailures(providerFailures),
                        code: "no_playable_stream", providerFailures: providerFailures });
                    return;
                }
                var provider = priority[idx];
                var raw = sources[provider];
                if (!raw) {
                    providerFailures.push({ provider: provider, reason: "source unavailable" });
                    tryProvider(idx + 1);
                    return;
                }
                if (raw.indexOf("--") !== 0) {
                    providerFailures.push({ provider: provider, reason: "unsupported source format" });
                    tryProvider(idx + 1);
                    return;
                }
                var decoded = _aaDecodeUrl(raw.substring(2));
                if (!decoded) {
                    providerFailures.push({ provider: provider, reason: "failed to decode source" });
                    tryProvider(idx + 1);
                    return;
                }
                var providerUrl = "https://" + _AA_BASE + decoded;

                _aaFetch(providerUrl, function(fetchErr, response) {
                    if (fetchErr) {
                        providerFailures.push({ provider: provider, reason: fetchErr });
                        tryProvider(idx + 1);
                        return;
                    }
                    var headers = { "User-Agent": _AA_AGENT, "Referer": _AA_REFERER };
                    var linkRe = /"link":"([^"]+)"[^}]*"resolutionStr":"([^"]+)"/g;
                    var links = [];
                    var match;
                    while ((match = linkRe.exec(response)) !== null) {
                        links.push([match[1], match[2]]);
                    }
                    var directMp4 = links.filter(function(pair) { return _aaIsDirectMp4Quality(pair[1]); });
                    if (directMp4.length > 0) {
                        var variants = _aaBuildQualityVariants(directMp4);
                        var picked = _aaPickQuality(variants.map(function(v) { return [v.url, v.quality]; }), qualityPref);
                        callback(null, { url: picked[0], referer: _AA_REFERER, type: "mp4",
                            provider: provider, http_headers: headers, metadata: metadata });
                        return;
                    }
                    if (response.toLowerCase().indexOf('"error"') !== -1) {
                        providerFailures.push({ provider: provider, reason: "provider returned an error response" });
                        tryProvider(idx + 1);
                        return;
                    }
                    var hlsMatch = response.match(/"url":"(https?:\/\/[^"]+master\.m3u8[^"]*)"/);
                    if (hlsMatch) {
                        var refMatch = response.match(/"Referer":"([^"]+)"/);
                        var finalUrl = _aaJsonUnescape(hlsMatch[1]);
                        var finalRef = refMatch ? _aaJsonUnescape(refMatch[1]) : _AA_REFERER;
                        headers.Referer = finalRef;
                        callback(null, { url: finalUrl, referer: finalRef, type: "hls",
                            provider: provider, http_headers: headers, metadata: metadata });
                        return;
                    }
                    providerFailures.push({ provider: provider, reason: "no playable links returned" });
                    tryProvider(idx + 1);
                });
            }
            tryProvider(0);
        });
    });
}

function _aaResolutionValue(value) {
    var match = (value || "").match(/(\d+)/);
    return match ? parseInt(match[1]) || 0 : 0;
}

function _aaIsDirectMp4Quality(label) {
    var text = (label || "").toLowerCase().trim();
    return _aaResolutionValue(text) > 0 || text === "source" || text === "default" || text === "original";
}

function _aaBuildQualityVariants(links) {
    links.sort(function(a, b) { return _aaResolutionValue(b[1]) - _aaResolutionValue(a[1]); });
    var variants = [], seen = {};
    for (var i = 0; i < links.length; i++) {
        var url = _aaJsonUnescape(links[i][0]);
        if (url.indexOf("repackager.wixmp.com") !== -1) {
            url = url.replace(/repackager\.wixmp\.com\//, "");
            url = url.replace(/\.urlset.*$/, "");
        }
        var label = _aaNormaliseVariantLabel(links[i][1], "mp4");
        var key = url + "|" + label;
        if (seen[key]) continue;
        seen[key] = true;
        variants.push({ url: url, quality: label, label: label, type: "mp4" });
    }
    return variants;
}

function _aaNormaliseVariantLabel(label, streamType) {
    var text = (label || "").trim();
    var lowered = text.toLowerCase();
    if (streamType === "hls" || lowered === "hls" || lowered === "m3u8" || lowered === "auto") return "Auto";
    return text || "Auto";
}

function _aaPickQuality(links, qualityPref) {
    links.sort(function(a, b) { return _aaResolutionValue(b[1]) - _aaResolutionValue(a[1]); });
    if (qualityPref === "best" || !qualityPref) return links[0];
    var target = parseInt(qualityPref) || 0;
    if (target <= 0) return links[0];
    var atOrBelow = links.filter(function(pair) { return _aaResolutionValue(pair[1]) <= target; });
    return atOrBelow.length > 0 ? atOrBelow[0] : links[links.length - 1];
}

function _aaJsonUnescape(value) {
    var text = value || "";
    try { return JSON.parse('"' + text.replace(/"/g, '\\"') + '"'); }
    catch (e) { return text.replace(/\\\//g, "/").replace(/\\u0026/g, "&"); }
}

function _aaSummariseFailures(failures) {
    if (!failures || !failures.length) return "No playable stream was available for this episode.";
    var summary = [];
    for (var i = 0; i < Math.min(3, failures.length); i++) {
        summary.push(failures[i].provider + ": " + failures[i].reason);
    }
    var detail = summary.join("; ");
    if (failures.length > 3) detail += "; +" + (failures.length - 3) + " more";
    var allUnavailable = true;
    for (var j = 0; j < failures.length; j++) {
        if (failures[j].reason !== "source unavailable") { allUnavailable = false; break; }
    }
    if (allUnavailable) return "No compatible providers were available for this episode.";
    return "No playable stream was available for this episode. " + detail;
}
