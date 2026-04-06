function mangaIdForChapter(chapter) {
    if (!chapter || !chapter.relationships) {
        return "";
    }

    for (var i = 0; i < chapter.relationships.length; i++) {
        var rel = chapter.relationships[i];
        if (rel.type === "manga") {
            return rel.id || "";
        }
    }

    return "";
}

function resolveTargetMangaId(selectedManga, currentChapter) {
    if (selectedManga && selectedManga.id) {
        return selectedManga.id;
    }
    return mangaIdForChapter(currentChapter);
}

function buildReadMarkerMap(dataArray) {
    var map = {};
    if (!dataArray || Object.prototype.toString.call(dataArray) !== "[object Array]") {
        return map;
    }

    for (var i = 0; i < dataArray.length; i++) {
        var id = String(dataArray[i] || "").trim();
        if (id !== "") {
            map[id] = true;
        }
    }

    return map;
}

function readingStatusLabel(value) {
    var labels = {
        "": "Set status...",
        "reading": "Reading",
        "on_hold": "On Hold",
        "plan_to_read": "Plan to Read",
        "dropped": "Dropped",
        "re_reading": "Re-reading",
        "completed": "Completed"
    };
    var key = String(value || "").trim();
    return labels[key] || key;
}
