function normalizePageEntry(pageEntry) {
    if (pageEntry === null || pageEntry === undefined) {
        return null;
    }

    var sourceValue = "";
    var canonicalSourceValue = "";
    var visibleValue = false;
    var pageIdentityValue = "";
    var cacheKeyValue = "";
    var chapterIdValue = "";
    var qualityModeValue = "";
    var pageIndexValue = -1;

    if (typeof pageEntry === "string") {
        sourceValue = String(pageEntry || "").trim();
        canonicalSourceValue = sourceValue;
    } else if (typeof pageEntry === "object") {
        sourceValue = String(pageEntry.source || pageEntry.canonicalSource || "").trim();
        canonicalSourceValue = String(pageEntry.canonicalSource || sourceValue).trim();
        visibleValue = !!pageEntry.visible;
        pageIdentityValue = String(pageEntry.pageIdentity || "").trim();
        cacheKeyValue = String(pageEntry.cacheKey || "").trim();
        chapterIdValue = String(pageEntry.chapterId || "").trim();
        qualityModeValue = String(pageEntry.qualityMode || "").trim();

        var numericIndex = Number(pageEntry.pageIndex);
        if (!isNaN(numericIndex) && numericIndex >= 0) {
            pageIndexValue = Math.round(numericIndex);
        }
    }

    if (sourceValue === "" || canonicalSourceValue === "") {
        return null;
    }

    if (pageIdentityValue === "") {
        pageIdentityValue = pageIdentityFromSource(canonicalSourceValue);
    }

    return {
        source: sourceValue,
        canonicalSource: canonicalSourceValue,
        visible: visibleValue,
        pageIdentity: pageIdentityValue,
        cacheKey: cacheKeyValue,
        chapterId: chapterIdValue,
        qualityMode: qualityModeValue,
        pageIndex: pageIndexValue
    };
}

function pageIdentityFromSource(sourceValue) {
    var source = String(sourceValue || "").trim();
    if (source === "") {
        return "";
    }

    var sanitized = source;
    var queryIndex = sanitized.indexOf("?");
    if (queryIndex >= 0) {
        sanitized = sanitized.substring(0, queryIndex);
    }
    var hashIndex = sanitized.indexOf("#");
    if (hashIndex >= 0) {
        sanitized = sanitized.substring(0, hashIndex);
    }

    var lastSlash = sanitized.lastIndexOf("/");
    if (lastSlash >= 0 && lastSlash + 1 < sanitized.length) {
        return sanitized.substring(lastSlash + 1);
    }
    return sanitized;
}

function buildPageCacheKeyForValues(chapterIdValue, qualityModeValue, pageIdentityValue, fallbackIndex) {
    var chapterPart = String(chapterIdValue || "").trim();
    var qualityPart = String(qualityModeValue || "data-saver").trim();
    var pagePart = String(pageIdentityValue || "").trim();
    if (pagePart === "") {
        pagePart = "page-" + String(Math.max(0, Number(fallbackIndex || 0)));
    }

    return chapterPart + "::" + qualityPart + "::" + pagePart;
}

function pageCacheKeyForEntry(normalizedEntry, currentChapterId, currentQualityMode, fallbackIndex) {
    if (!normalizedEntry) {
        return "";
    }

    if (normalizedEntry.cacheKey && normalizedEntry.cacheKey !== "") {
        return normalizedEntry.cacheKey;
    }

    return buildPageCacheKeyForValues(
        normalizedEntry.chapterId || currentChapterId || "",
        normalizedEntry.qualityMode || currentQualityMode || "data-saver",
        normalizedEntry.pageIdentity,
        normalizedEntry.pageIndex >= 0 ? normalizedEntry.pageIndex : fallbackIndex);
}

function _cloneObject(sourceObj) {
    var out = {};
    if (!sourceObj || typeof sourceObj !== "object") {
        return out;
    }
    for (var key in sourceObj) {
        if (sourceObj.hasOwnProperty(key)) {
            out[key] = sourceObj[key];
        }
    }
    return out;
}

function _cloneArray(sourceList) {
    if (Object.prototype.toString.call(sourceList) !== "[object Array]") {
        return [];
    }
    return sourceList.slice(0);
}

function pruneCache(entries, lru, maxEntries, perChapterMax) {
    var nextEntries = _cloneObject(entries);
    var nextLru = _cloneArray(lru);
    var evicted = [];

    if (nextLru.length > 0 && perChapterMax > 0) {
        var chapterSeen = {};
        for (var i = nextLru.length - 1; i >= 0; i--) {
            var key = nextLru[i];
            var entry = nextEntries[key];
            if (!entry || entry.valid !== true) {
                continue;
            }

            var chapterKey = String(entry.chapterId || "");
            chapterSeen[chapterKey] = Number(chapterSeen[chapterKey] || 0) + 1;
            if (chapterSeen[chapterKey] > perChapterMax) {
                evicted.push(key);
                nextLru.splice(i, 1);
            }
        }
    }

    while (nextLru.length > maxEntries) {
        evicted.push(nextLru.shift());
    }

    for (var j = 0; j < evicted.length; j++) {
        var evictKey = evicted[j];
        var evictEntry = nextEntries[evictKey];
        if (!evictEntry) {
            continue;
        }
        evictEntry.valid = false;
        evictEntry.evicted = true;
        evictEntry.evictedAtMs = Date.now();
        nextEntries[evictKey] = evictEntry;
    }

    return {
        entries: nextEntries,
        lru: nextLru,
        evicted: evicted
    };
}

function touchCacheKey(entries, lru, cacheKey) {
    var key = String(cacheKey || "").trim();
    if (key === "") {
        return { entries: entries, lru: lru, changed: false };
    }

    var nextLru = _cloneArray(lru);
    var foundIndex = -1;
    for (var i = 0; i < nextLru.length; i++) {
        if (nextLru[i] === key) {
            foundIndex = i;
            break;
        }
    }

    if (foundIndex >= 0) {
        nextLru.splice(foundIndex, 1);
    }
    nextLru.push(key);

    return {
        entries: entries,
        lru: nextLru,
        changed: true
    };
}

function isPageCached(entries, cacheKey) {
    if (!entries || !cacheKey) {
        return false;
    }
    var entry = entries[cacheKey];
    return !!(entry && entry.valid === true);
}

function _isArray(value) {
    return Object.prototype.toString.call(value) === "[object Array]";
}

function buildRuntimePageEntries(atHomeResponse, qualityMode, currentChapterId) {
    if (!atHomeResponse || !atHomeResponse.baseUrl || !atHomeResponse.chapter) {
        return [];
    }

    var baseUrl = String(atHomeResponse.baseUrl || "").trim();
    while (baseUrl.length > 0 && baseUrl.charAt(baseUrl.length - 1) === "/") {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    if (baseUrl === "") {
        return [];
    }

    var chapter = atHomeResponse.chapter;
    var hash = chapter.hash || "";
    if (hash === "") {
        return [];
    }

    var requestedQuality = qualityMode === "data" ? "data" : "data-saver";
    var pathPart = requestedQuality === "data" ? "data" : "data-saver";
    var files = requestedQuality === "data" ? chapter.data : chapter.dataSaver;

    if (!_isArray(files) || files.length === 0) {
        files = requestedQuality === "data" ? chapter.dataSaver : chapter.data;
        pathPart = requestedQuality === "data" ? "data-saver" : "data";
    }

    if (!_isArray(files)) {
        return [];
    }

    var entries = [];
    for (var i = 0; i < files.length; i++) {
        var fileName = String(files[i] || "").trim();
        if (fileName === "") {
            continue;
        }

        var source = baseUrl + "/" + pathPart + "/" + hash + "/" + fileName;
        var identity = pageIdentityFromSource(fileName);

        entries.push({
            source: source,
            canonicalSource: source,
            visible: false,
            pageIdentity: identity,
            cacheKey: "",
            chapterId: currentChapterId || "",
            qualityMode: requestedQuality,
            pageIndex: i
        });
    }

    return entries;
}
