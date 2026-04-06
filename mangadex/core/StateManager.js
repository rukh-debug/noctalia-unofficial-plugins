function serializeState(state) {
    return {
        searchQuery: String(state.searchQuery || ""),
        qualityMode: String(state.qualityMode || "data-saver"),
        selectedMangaId: String(state.selectedMangaId || ""),
        selectedChapterId: String(state.selectedChapterId || ""),
        readerAnchor: state.readerAnchor || null,
        timestamp: state.timestamp || Math.floor(Date.now() / 1000)
    };
}

function deserializeState(jsonText, defaultQualityMode) {
    if (!jsonText || String(jsonText).trim() === "") {
        return null;
    }

    try {
        var cached = JSON.parse(jsonText);
        return {
            searchQuery: String(cached.searchQuery || ""),
            qualityMode: String(cached.qualityMode || defaultQualityMode || "data-saver"),
            selectedMangaId: String(cached.selectedMangaId || ""),
            selectedChapterId: String(cached.selectedChapterId || ""),
            readerAnchor: cached.readerAnchor || null,
            timestamp: Number(cached.timestamp || 0)
        };
    } catch (e) {
        return null;
    }
}

function normalizeAnchorData(anchorData, chapterIdFallback) {
    var source = anchorData && typeof anchorData === "object" ? anchorData : {};
    var chapterId = String(source.chapterId || chapterIdFallback || "").trim();
    if (chapterId === "") {
        return {
            chapterId: "",
            pageIdentity: "",
            pageIndex: 0,
            offsetRatio: 0,
            scrollY: 0,
            timestampMs: 0
        };
    }

    var pageIndex = Number(source.pageIndex);
    if (isNaN(pageIndex) || pageIndex < 0) {
        pageIndex = 0;
    }

    var scrollY = Number(source.scrollY);
    if (isNaN(scrollY) || scrollY < 0) {
        scrollY = 0;
    }

    var offsetRatio = Number(source.offsetRatio);
    if (isNaN(offsetRatio)) {
        offsetRatio = 0;
    }
    offsetRatio = Math.max(0, Math.min(1, offsetRatio));

    return {
        chapterId: chapterId,
        pageIdentity: String(source.pageIdentity || "").trim(),
        pageIndex: Math.round(pageIndex),
        offsetRatio: offsetRatio,
        scrollY: scrollY,
        timestampMs: Number(source.timestampMs || Date.now())
    };
}
