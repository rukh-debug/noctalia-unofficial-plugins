function _normalizeMangaId(item) {
    if (!item || typeof item !== "object") {
        return "";
    }
    return String(item.id || "").trim();
}

function mergeByMangaId(existingItems, incomingItems) {
    var existing = Object.prototype.toString.call(existingItems) === "[object Array]" ? existingItems : [];
    var incoming = Object.prototype.toString.call(incomingItems) === "[object Array]" ? incomingItems : [];

    var merged = [];
    var seen = {};
    var dedupedCount = 0;

    for (var i = 0; i < existing.length; i++) {
        var existingItem = existing[i];
        var existingId = _normalizeMangaId(existingItem);
        if (existingId === "" || seen[existingId] === true) {
            continue;
        }
        seen[existingId] = true;
        merged.push(existingItem);
    }

    var appendedCount = 0;
    for (var j = 0; j < incoming.length; j++) {
        var incomingItem = incoming[j];
        var incomingId = _normalizeMangaId(incomingItem);
        if (incomingId === "" || seen[incomingId] === true) {
            dedupedCount += 1;
            continue;
        }

        seen[incomingId] = true;
        merged.push(incomingItem);
        appendedCount += 1;
    }

    return {
        merged: merged,
        incomingCount: incoming.length,
        dedupedCount: dedupedCount,
        appendedCount: appendedCount
    };
}
