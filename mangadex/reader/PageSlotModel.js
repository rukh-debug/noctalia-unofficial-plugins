var STATE_LOADING = "loading";
var STATE_READY = "ready";
var STATE_ERROR = "error";
var STATE_STALE = "stale";

function normalizeStatus(statusValue) {
    var normalized = String(statusValue || "").toLowerCase().trim();
    if (normalized === STATE_READY || normalized === STATE_ERROR || normalized === STATE_STALE) {
        return normalized;
    }
    return STATE_LOADING;
}

function _normalizeIdentity(identityValue, fallbackIndex) {
    var identity = String(identityValue || "").trim();
    if (identity === "") {
        identity = "page-" + String(Math.max(0, Math.round(Number(fallbackIndex || 0))));
    }
    return identity;
}

function buildSlotKey(chapterIdValue, pageIdentityValue, fallbackIndex) {
    var chapterId = String(chapterIdValue || "").trim();
    var identity = _normalizeIdentity(pageIdentityValue, fallbackIndex);
    return chapterId + "::" + identity;
}

function buildSlotKeyForEntry(chapterIdValue, pageEntry, fallbackIndex) {
    if (!pageEntry || typeof pageEntry !== "object") {
        return buildSlotKey(chapterIdValue, "", fallbackIndex);
    }

    var identity = String(pageEntry.pageIdentity || pageEntry.canonicalSource || pageEntry.source || "").trim();
    var resolvedChapter = String(pageEntry.chapterId || chapterIdValue || "").trim();
    return buildSlotKey(resolvedChapter, identity, fallbackIndex);
}

function cloneMap(sourceMap) {
    var out = {};
    if (!sourceMap || typeof sourceMap !== "object") {
        return out;
    }

    for (var key in sourceMap) {
        if (!sourceMap.hasOwnProperty(key)) {
            continue;
        }

        var value = sourceMap[key];
        if (!value || typeof value !== "object") {
            continue;
        }

        var cloneValue = {};
        for (var nestedKey in value) {
            if (value.hasOwnProperty(nestedKey)) {
                cloneValue[nestedKey] = value[nestedKey];
            }
        }
        out[key] = cloneValue;
    }

    return out;
}

function setSlotState(sourceMap, slotKey, patch) {
    var nextMap = cloneMap(sourceMap);
    var key = String(slotKey || "").trim();
    if (key === "") {
        return nextMap;
    }

    var existing = nextMap[key] && typeof nextMap[key] === "object" ? nextMap[key] : {};
    var nextEntry = {};

    for (var ek in existing) {
        if (existing.hasOwnProperty(ek)) {
            nextEntry[ek] = existing[ek];
        }
    }

    var sourcePatch = patch && typeof patch === "object" ? patch : {};
    for (var pk in sourcePatch) {
        if (sourcePatch.hasOwnProperty(pk)) {
            nextEntry[pk] = sourcePatch[pk];
        }
    }

    nextEntry.status = normalizeStatus(nextEntry.status);
    nextEntry.updatedAtMs = Number(Date.now());
    nextMap[key] = nextEntry;

    return nextMap;
}

function hydrateForEntries(sourceMap, chapterId, entries) {
    var nextMap = {};
    var base = cloneMap(sourceMap);
    var chapter = String(chapterId || "").trim();
    var list = Object.prototype.toString.call(entries) === "[object Array]" ? entries : [];

    for (var i = 0; i < list.length; i++) {
        var entry = list[i];
        var slotKey = buildSlotKeyForEntry(chapter, entry, i);
        var existing = base[slotKey] && typeof base[slotKey] === "object" ? base[slotKey] : null;

        nextMap[slotKey] = {
            status: normalizeStatus(existing ? existing.status : STATE_LOADING),
            chapterId: chapter,
            pageIndex: i,
            pageIdentity: String(entry?.pageIdentity || "").trim(),
            source: String(entry?.source || "").trim(),
            lastError: existing ? String(existing.lastError || "") : "",
            failureCount: existing ? Number(existing.failureCount || 0) : 0,
            updatedAtMs: Number(Date.now())
        };
    }

    return nextMap;
}

function getSlotState(sourceMap, slotKey) {
    var map = sourceMap && typeof sourceMap === "object" ? sourceMap : {};
    var key = String(slotKey || "").trim();
    if (key === "" || !map[key] || typeof map[key] !== "object") {
        return {
            status: STATE_LOADING,
            failureCount: 0,
            lastError: ""
        };
    }

    var entry = map[key];
    return {
        status: normalizeStatus(entry.status),
        failureCount: Number(entry.failureCount || 0),
        lastError: String(entry.lastError || ""),
        updatedAtMs: Number(entry.updatedAtMs || 0)
    };
}
