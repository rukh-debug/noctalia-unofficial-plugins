var MAX_SEARCH_OFFSET = 10000;

function clampLimit(limitValue, fallbackValue) {
    var fallback = Number(fallbackValue || 20);
    if (isNaN(fallback) || fallback <= 0) {
        fallback = 20;
    }

    var numeric = Number(limitValue);
    if (isNaN(numeric) || numeric <= 0) {
        numeric = fallback;
    }

    return Math.max(1, Math.min(100, Math.round(numeric)));
}

function clampOffset(offsetValue) {
    var numeric = Number(offsetValue);
    if (isNaN(numeric) || numeric < 0) {
        numeric = 0;
    }
    return Math.max(0, Math.min(MAX_SEARCH_OFFSET, Math.round(numeric)));
}

function computeNextOffset(requestOffset, appendedCount) {
    var start = clampOffset(requestOffset);
    var increment = Math.max(0, Math.round(Number(appendedCount || 0)));
    return clampOffset(start + increment);
}

function hasMoreResults(incomingCount, pageSize, nextOffset) {
    var normalizedIncoming = Math.max(0, Math.round(Number(incomingCount || 0)));
    var normalizedPageSize = clampLimit(pageSize, 20);
    var offset = clampOffset(nextOffset);
    return normalizedIncoming >= normalizedPageSize && offset < MAX_SEARCH_OFFSET;
}
