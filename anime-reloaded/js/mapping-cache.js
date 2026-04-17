var MappingCache = (function() {
    var _data = { version: 1, showMappings: {} };

    function _makeKey(metadataProvider, metadataId, streamProvider) {
        return metadataProvider + ":" + metadataId + ":" + streamProvider;
    }

    function _normaliseEntry(entry) {
        var item = entry || {};
        item.status = item.status || (item.streamId ? "mapped" : "unknown");
        item.targetProvider = item.targetProvider || item.streamProvider || "";
        item.targetId = item.targetId || item.streamId || "";
        item.streamId = item.streamId || "";
        item.reason = item.reason || "";
        item.confidence = item.confidence || 0;
        item.candidates = Array.isArray(item.candidates) ? item.candidates : [];
        return item;
    }

    function reset() { _data = { version: 1, showMappings: {} }; }

    function loadFromJson(json) {
        if (!json || typeof json !== "object") return;
        if (json.showMappings) _data.showMappings = json.showMappings;
    }

    function toJson() { return { version: _data.version, showMappings: _data.showMappings }; }

    function getMappingRecord(metadataProvider, metadataId, streamProvider) {
        metadataProvider = (metadataProvider || "").trim();
        metadataId = (metadataId || "").trim();
        streamProvider = (streamProvider || "").trim();
        if (!metadataProvider || !metadataId || !streamProvider) return {};
        var key = _makeKey(metadataProvider, metadataId, streamProvider);
        return _normaliseEntry(_data.showMappings[key] || {});
    }

    function rememberMappingResult(metadataProvider, metadataId, streamProvider, opts) {
        opts = opts || {};
        metadataProvider = (metadataProvider || "").trim();
        metadataId = (metadataId || "").trim();
        streamProvider = (streamProvider || "").trim();
        var streamId = (opts.streamId || "").trim();
        var status = (opts.status || "").trim();
        if (!metadataProvider || !metadataId || !streamProvider || !status) return;
        var key = _makeKey(metadataProvider, metadataId, streamProvider);
        _data.showMappings[key] = {
            metadataProvider: metadataProvider,
            metadataId: metadataId,
            streamProvider: streamProvider,
            streamId: streamId,
            targetProvider: streamProvider,
            targetId: streamId,
            status: status,
            confidence: opts.confidence || 0,
            reason: (opts.reason || "").trim(),
            candidates: Array.isArray(opts.candidates) ? opts.candidates : [],
            updatedAt: Math.floor(Date.now() / 1000)
        };
    }

    function rememberShowMapping(metadataProvider, metadataId, streamProvider, streamId) {
        rememberMappingResult(metadataProvider, metadataId, streamProvider, {
            status: "mapped", streamId: streamId, confidence: 1
        });
    }

    function rememberProviderMapping(sourceProvider, sourceId, targetProvider, targetId, opts) {
        opts = opts || {};
        rememberMappingResult(sourceProvider, sourceId, targetProvider, {
            status: opts.status || "mapped",
            streamId: targetId,
            confidence: opts.confidence !== undefined ? opts.confidence : 1,
            reason: opts.reason || "",
            candidates: opts.candidates
        });
    }

    function getProviderShowId(sourceProvider, sourceId, targetProvider) {
        return getStreamShowId(sourceProvider, sourceId, targetProvider);
    }

    function getSourceShowId(sourceProvider, targetProvider, targetId) {
        sourceProvider = (sourceProvider || "").trim();
        targetProvider = (targetProvider || "").trim();
        targetId = (targetId || "").trim();
        if (!sourceProvider || !targetProvider || !targetId) return "";
        var mappings = _data.showMappings || {};
        var keys = Object.keys(mappings);
        for (var i = 0; i < keys.length; i++) {
            var entry = _normaliseEntry(mappings[keys[i]]);
            if (entry.status !== "mapped") continue;
            if ((entry.metadataProvider || "").trim() !== sourceProvider) continue;
            if ((entry.targetProvider || "").trim() !== targetProvider) continue;
            if ((entry.targetId || "").trim() !== targetId) continue;
            return (entry.metadataId || "").trim();
        }
        return "";
    }

    function getStreamShowId(metadataProvider, metadataId, streamProvider) {
        metadataProvider = (metadataProvider || "").trim();
        metadataId = (metadataId || "").trim();
        streamProvider = (streamProvider || "").trim();
        if (!metadataProvider || !metadataId || !streamProvider) return "";
        if (metadataProvider === streamProvider) return metadataId;
        var entry = getMappingRecord(metadataProvider, metadataId, streamProvider);
        if (entry.status !== "mapped") return "";
        return (entry.streamId || "").trim();
    }

    function decorateShow(show, metadataProvider, streamProvider, streamId) {
        var item = JSON.parse(JSON.stringify(show || {}));
        var metadataId = (item.id || "").trim();
        var refs = item.providerRefs;
        if (!refs || typeof refs !== "object") refs = {};
        refs.metadata = { provider: metadataProvider, id: metadataId };
        var resolvedStreamId = (streamId || "").trim();
        if (!resolvedStreamId && metadataProvider === streamProvider)
            resolvedStreamId = metadataId;
        if (!resolvedStreamId)
            resolvedStreamId = getStreamShowId(metadataProvider, metadataId, streamProvider);
        if (resolvedStreamId) {
            refs.stream = { provider: streamProvider, id: resolvedStreamId };
            rememberShowMapping(metadataProvider, metadataId, streamProvider, resolvedStreamId);
        } else {
            delete refs.stream;
        }
        item.providerRefs = refs;
        return item;
    }

    return {
        reset: reset,
        loadFromJson: loadFromJson,
        toJson: toJson,
        getMappingRecord: getMappingRecord,
        rememberMappingResult: rememberMappingResult,
        rememberShowMapping: rememberShowMapping,
        rememberProviderMapping: rememberProviderMapping,
        getProviderShowId: getProviderShowId,
        getSourceShowId: getSourceShowId,
        getStreamShowId: getStreamShowId,
        decorateShow: decorateShow
    };
})();

function _cleanTitle(value) {
    var text = (value || "").toLowerCase();
    text = text.replace(/\([^)]*\)/g, " ");
    text = text.replace(/[^a-z0-9]+/g, " ");
    text = text.replace(/\s+/g, " ").trim();
    return text;
}

function _sequenceRatio(a, b) {
    if (a === b) return 1.0;
    if (!a || !b) return 0.0;
    var al = a.length, bl = b.length;
    if (al === 0 && bl === 0) return 1.0;
    if (al === 0 || bl === 0) return 0.0;
    var prev = [];
    var curr = [];
    for (var j = 0; j <= bl; j++) prev[j] = 0;
    for (var i = 1; i <= al; i++) {
        curr[0] = 0;
        for (var j2 = 1; j2 <= bl; j2++) {
            if (a[i - 1] === b[j2 - 1]) curr[j2] = prev[j2 - 1] + 1;
            else curr[j2] = Math.max(prev[j2], curr[j2 - 1]);
        }
        var tmp = prev; prev = curr; curr = tmp;
    }
    return (2.0 * prev[bl]) / (al + bl);
}

function _anilistAllAnimeMapperSearchCandidates(media, mode, callback) {
    var variants = _anilistTitleVariants(media);
    var merged = {};
    var index = 0;
    var maxQueries = Math.min(variants.length, 6);

    function nextQuery() {
        if (index >= maxQueries || Object.keys(merged).length >= 20) {
            var results = [];
            var keys = Object.keys(merged);
            for (var k = 0; k < keys.length; k++) results.push(merged[keys[k]]);
            callback(results);
            return;
        }
        var query = variants[index];
        index++;
        _allanimeSearchShows(query, mode, 1, "allanime", function(err, data) {
            if (!err && data && data.results) {
                for (var r = 0; r < data.results.length; r++) {
                    var item = data.results[r];
                    if (item.id) merged[item.id] = item;
                }
            }
            nextQuery();
        });
    }
    nextQuery();
}

function _anilistTitleVariants(media) {
    var title = (media || {}).title || {};
    var values = [title.english, title.romaji, title.native];
    var synonyms = media.synonyms || [];
    for (var s = 0; s < synonyms.length; s++) values.push(synonyms[s]);
    var seen = {};
    var variants = [];
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

function _anilistAllAnimeMapResolve(media, mode, callback) {
    var metadataId = String((media || {}).id || "").trim();
    var cached = MappingCache.getMappingRecord("anilist", metadataId, "allanime");
    if (cached.status === "mapped" && cached.streamId) {
        callback(null, {
            status: "mapped", streamId: cached.streamId,
            confidence: cached.confidence || 1, reason: cached.reason || "cached mapping",
            candidates: cached.candidates || [], cached: true
        });
        return;
    }

    _anilistAllAnimeMapperSearchCandidates(media, mode, function(candidates) {
        if (!candidates || candidates.length === 0) {
            var result = { status: "unmapped", streamId: "", confidence: 0,
                reason: "No AllAnime candidates were found for this AniList entry.", candidates: [] };
            MappingCache.rememberMappingResult("anilist", metadataId, "allanime", {
                status: result.status, streamId: "", confidence: 0, reason: result.reason
            });
            callback(null, result);
            return;
        }

        var ranked = [];
        for (var i = 0; i < candidates.length; i++) {
            ranked.push(_scoreAniListAllAnimeCandidate(media, candidates[i]));
        }
        ranked.sort(function(a, b) { return b.score - a.score; });

        var top = ranked[0];
        var secondScore = ranked.length > 1 ? ranked[1].score : -999;
        var margin = top.score - secondScore;

        var candidateDebug = [];
        for (var d = 0; d < Math.min(5, ranked.length); d++) {
            var c = ranked[d].candidate;
            candidateDebug.push({
                id: c.id, title: c.englishName || c.name || "",
                year: (c.season || {}).year || null, type: c.type || "",
                episodes: _maxAvailableEpisodes(c), score: ranked[d].score,
                reasons: (ranked[d].reasons || []).slice(0, 4)
            });
        }

        var accept = top.score >= 68 && (margin >= 10 || top.exactTitle || top.titleRatio >= 0.94);
        var result2;
        if (accept) {
            result2 = {
                status: "mapped", streamId: top.candidate.id || "",
                confidence: Math.min(1, Math.round(Math.max(0, top.score) / 100 * 1000) / 1000),
                reason: "Matched AniList entry to AllAnime using title/season heuristics.",
                candidates: candidateDebug
            };
        } else {
            result2 = {
                status: "uncertain", streamId: "",
                confidence: Math.min(1, Math.round(Math.max(0, top.score) / 100 * 1000) / 1000),
                reason: "Multiple AllAnime candidates were too close to choose safely.",
                candidates: candidateDebug
            };
        }

        MappingCache.rememberMappingResult("anilist", metadataId, "allanime", {
            status: result2.status, streamId: result2.streamId,
            confidence: result2.confidence, reason: result2.reason, candidates: result2.candidates
        });
        callback(null, result2);
    });
}

function _scoreAniListAllAnimeCandidate(media, candidate) {
    var reasons = [];
    var score = 0;

    var variants = [];
    var titleList = _anilistTitleVariants(media);
    for (var v = 0; v < titleList.length; v++) {
        var ct = _cleanTitle(titleList[v]);
        if (ct) variants.push(ct);
    }
    var candidateTitles = [
        _cleanTitle(candidate.englishName || ""),
        _cleanTitle(candidate.name || ""),
        _cleanTitle(candidate.nativeName || "")
    ].filter(function(t) { return t.length > 0; });

    var bestRatio = 0, exactTitle = false, partialTitle = false;
    for (var si = 0; si < variants.length; si++) {
        for (var ti = 0; ti < candidateTitles.length; ti++) {
            if (!variants[si] || !candidateTitles[ti]) continue;
            var ratio = _sequenceRatio(variants[si], candidateTitles[ti]);
            if (ratio > bestRatio) bestRatio = ratio;
            if (variants[si] === candidateTitles[ti]) exactTitle = true;
            else if (variants[si].indexOf(candidateTitles[ti]) !== -1 || candidateTitles[ti].indexOf(variants[si]) !== -1) partialTitle = true;
        }
    }

    if (exactTitle) { score += 65; reasons.push("exact title"); }
    else if (partialTitle) { score += 38; reasons.push("partial title"); }
    score += bestRatio * 30;
    reasons.push("title ratio " + bestRatio.toFixed(2));

    var mediaYear = parseInt(media.seasonYear) || 0;
    var candidateYear = parseInt(((candidate.season || {}).year)) || 0;
    if (mediaYear && candidateYear) {
        if (mediaYear === candidateYear) { score += 18; reasons.push("same year"); }
        else if (Math.abs(mediaYear - candidateYear) === 1) { score += 8; reasons.push("near year"); }
        else { score -= 12; reasons.push("year mismatch"); }
    }

    var mediaQuarter = (media.season || "").trim();
    var candidateQuarter = ((candidate.season || {}).quarter || "").trim();
    if (mediaQuarter && candidateQuarter) {
        if (mediaQuarter.toLowerCase() === candidateQuarter.toLowerCase()) { score += 6; reasons.push("same season"); }
        else score -= 2;
    }

    var wantedFormat = _formatGroup(media.format);
    var candFormat = _candidateFormat(candidate.type);
    if (wantedFormat && candFormat) {
        if (wantedFormat === candFormat) { score += 15; reasons.push("format match"); }
        else { score -= 12; reasons.push("format mismatch"); }
    }

    var wantedEp = _episodeHint(media);
    var candidateEp = _maxAvailableEpisodes(candidate);
    if (wantedEp > 0 && candidateEp > 0) {
        var diff = Math.abs(wantedEp - candidateEp);
        if (diff === 0) { score += 16; reasons.push("episode exact"); }
        else if (diff <= 2) { score += 9; reasons.push("episode near"); }
        else if (diff <= 6) score += 3;
        else { score -= Math.min(10, diff / 10); reasons.push("episode mismatch"); }
    }

    return { candidate: candidate, score: Math.round(score * 100) / 100,
        exactTitle: exactTitle, titleRatio: Math.round(bestRatio * 1000) / 1000, reasons: reasons };
}

function _formatGroup(fmt) {
    var v = (fmt || "").toUpperCase();
    if (v === "TV" || v === "TV_SHORT") return "TV";
    if (v === "MOVIE") return "MOVIE";
    if (v === "ONA") return "ONA";
    if (v === "OVA") return "OVA";
    if (v === "SPECIAL") return "SPECIAL";
    return v;
}

function _candidateFormat(fmt) {
    var v = (fmt || "").toUpperCase().replace(/ /g, "_");
    if (v === "TV") return "TV";
    if (v === "MOVIE") return "MOVIE";
    if (v === "SPECIAL") return "SPECIAL";
    if (v === "OVA") return "OVA";
    if (v === "ONA") return "ONA";
    return v;
}

function _episodeHint(media) {
    if ((media || {}).status === "RELEASING") {
        var nextAiring = media.nextAiringEpisode || {};
        var nextEp = parseInt(nextAiring.episode) || 0;
        if (nextEp > 1) return nextEp - 1;
    }
    return parseInt(media.episodes) || 0;
}

function _maxAvailableEpisodes(item) {
    var avail = (item || {}).availableEpisodes || {};
    return Math.max(parseInt(avail.sub) || 0, parseInt(avail.dub) || 0, parseInt(avail.raw) || 0);
}
