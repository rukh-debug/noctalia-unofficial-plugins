var _diagnostics = null;

function setDiagnostics(diagnostics) {
    _diagnostics = diagnostics || null;
}

function _diag(method, eventName, context, message) {
    if (!_diagnostics || typeof _diagnostics[method] !== "function") {
        return;
    }
    _diagnostics[method](eventName, context || {}, message || "");
}

function _isArray(value) {
    return Object.prototype.toString.call(value) === "[object Array]";
}

function pickLocalized(localizedObj, preferredLanguage) {
    if (!localizedObj || typeof localizedObj !== "object") {
        return "";
    }

    if (preferredLanguage && localizedObj[preferredLanguage]) {
        return localizedObj[preferredLanguage];
    }

    if (localizedObj.en) {
        return localizedObj.en;
    }

    for (var key in localizedObj) {
        if (localizedObj.hasOwnProperty(key) && localizedObj[key]) {
            return localizedObj[key];
        }
    }

    return "";
}

function mangaTitle(manga, preferredLanguage) {
    if (!manga || !manga.attributes) {
        return "Unknown title";
    }

    var title = pickLocalized(manga.attributes.title, preferredLanguage);
    if (!title || title.trim() === "") {
        return "Untitled";
    }
    return title;
}

function mangaDescription(manga, preferredLanguage) {
    if (!manga || !manga.attributes) {
        return "";
    }
    return pickLocalized(manga.attributes.description, preferredLanguage);
}

function chapterLabel(chapter) {
    if (!chapter || !chapter.attributes) {
        return "Unknown chapter";
    }

    var volume = chapter.attributes.volume;
    var chapterNumber = chapter.attributes.chapter;
    var chapterTitle = chapter.attributes.title || "";

    var left = "";
    if (volume && volume !== "") {
        left += "Vol. " + volume + " ";
    }
    if (chapterNumber && chapterNumber !== "") {
        left += "Ch. " + chapterNumber;
    } else {
        left += "Chapter";
    }

    if (chapterTitle && chapterTitle !== "") {
        return left + " - " + chapterTitle;
    }

    return left;
}

function _chapterSortNumber(chapter) {
    if (!chapter || !chapter.attributes) {
        return Number.MAX_VALUE;
    }

    var raw = chapter.attributes.chapter;
    if (raw === null || raw === undefined || raw === "") {
        return Number.MAX_VALUE;
    }

    var numberValue = parseFloat(raw);
    if (isNaN(numberValue)) {
        return Number.MAX_VALUE;
    }

    return numberValue;
}

function sortChapters(chapters) {
    if (!_isArray(chapters)) {
        return [];
    }

    var copy = chapters.slice(0);
    copy.sort(function(a, b) {
        var aNum = _chapterSortNumber(a);
        var bNum = _chapterSortNumber(b);

        if (aNum !== bNum) {
            return aNum - bNum;
        }

        var aTs = a && a.attributes && a.attributes.publishAt ? a.attributes.publishAt : "";
        var bTs = b && b.attributes && b.attributes.publishAt ? b.attributes.publishAt : "";

        if (aTs < bTs) {
            return -1;
        }
        if (aTs > bTs) {
            return 1;
        }

        return 0;
    });

    return copy;
}

function buildPageUrls(atHomeResponse, qualityMode) {
    if (!atHomeResponse || !atHomeResponse.baseUrl || !atHomeResponse.chapter) {
        _diag("warn", "reader_service.page_urls.invalid_payload", {
            hasResponse: !!atHomeResponse,
            hasBaseUrl: !!(atHomeResponse && atHomeResponse.baseUrl),
            hasChapter: !!(atHomeResponse && atHomeResponse.chapter)
        }, "Cannot build page URLs due to invalid At-Home payload");
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
        _diag("warn", "reader_service.page_urls.missing_hash", {}, "Cannot build page URLs because chapter hash is missing");
        return [];
    }

    var requestedQuality = qualityMode === "data" ? "data" : "data-saver";
    var pathPart = requestedQuality === "data" ? "data" : "data-saver";

    var files = requestedQuality === "data" ? chapter.data : chapter.dataSaver;

    if (!_isArray(files) || files.length === 0) {
        files = requestedQuality === "data" ? chapter.dataSaver : chapter.data;
        pathPart = requestedQuality === "data" ? "data-saver" : "data";
        _diag("warn", "reader_service.page_urls.quality_fallback", {
            requestedQuality: requestedQuality,
            fallbackPath: pathPart
        }, "Requested quality had no files; using fallback array");
    }

    if (!_isArray(files)) {
        _diag("warn", "reader_service.page_urls.invalid_files", {
            requestedQuality: requestedQuality
        }, "At-Home files payload is invalid");
        return [];
    }

    var urls = [];
    for (var i = 0; i < files.length; i++) {
        var fileName = String(files[i] || "").trim();
        if (fileName === "") {
            continue;
        }

        urls.push(baseUrl + "/" + pathPart + "/" + hash + "/" + fileName);
    }

    _diag("debug", "reader_service.page_urls.built", {
        requestedQuality: requestedQuality,
        finalPathPart: pathPart,
        pageCount: urls.length
    }, "Constructed chapter page URLs");

    return urls;
}

function isChapterRead(readMap, chapterId) {
    if (!readMap || !chapterId) {
        return false;
    }
    return readMap[chapterId] === true;
}
