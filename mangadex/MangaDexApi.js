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

function _diagChild(baseContext, extraContext) {
    if (_diagnostics && typeof _diagnostics.childContext === "function") {
        return _diagnostics.childContext(baseContext || {}, extraContext || {});
    }

    var out = {};
    var key;
    if (baseContext && typeof baseContext === "object") {
        for (key in baseContext) {
            if (baseContext.hasOwnProperty(key)) {
                out[key] = baseContext[key];
            }
        }
    }
    if (extraContext && typeof extraContext === "object") {
        for (key in extraContext) {
            if (extraContext.hasOwnProperty(key)) {
                out[key] = extraContext[key];
            }
        }
    }
    return out;
}

var API_BASE = "https://api.mangadex.org";

var SEARCH_LIMIT_MAX = 100;
var FEED_LIMIT_MAX = 500;
var MAX_COLLECTION_OFFSET = 10000;

var DEFAULT_TIMEOUT_MS = 20000;
var DEFAULT_PACING_MS = 250;
var DEFAULT_MAX_RETRIES = 2;
var DEFAULT_BACKOFF_BASE_MS = 400;
var MAX_BACKOFF_MS = 15000;

var _requestSequence = 0;
var _lastRequestStartMs = 0;

function _isArray(value) {
    return Object.prototype.toString.call(value) === "[object Array]";
}

function _safeNumber(value, fallback, minValue, maxValue) {
    var numeric = Number(value);
    if (isNaN(numeric)) {
        numeric = Number(fallback);
    }

    if (!isNaN(minValue)) {
        numeric = Math.max(minValue, numeric);
    }
    if (!isNaN(maxValue)) {
        numeric = Math.min(maxValue, numeric);
    }

    return numeric;
}

function _normalizeOffset(offsetValue) {
    return _safeNumber(offsetValue, 0, 0, MAX_COLLECTION_OFFSET);
}

function _encodeQuery(params) {
    var parts = [];
    if (!params) {
        return "";
    }

    for (var key in params) {
        if (!params.hasOwnProperty(key)) {
            continue;
        }

        var value = params[key];
        if (value === undefined || value === null || value === "") {
            continue;
        }

        if (_isArray(value)) {
            for (var i = 0; i < value.length; i++) {
                if (value[i] === undefined || value[i] === null || value[i] === "") {
                    continue;
                }
                parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(value[i])));
            }
        } else {
            parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(value)));
        }
    }

    return parts.join("&");
}

function _extractHost(url) {
    var stripped = url.replace(/^https?:\/\//, "");
    var slashIndex = stripped.indexOf("/");
    var hostPort = slashIndex >= 0 ? stripped.substring(0, slashIndex) : stripped;
    var colonIndex = hostPort.indexOf(":");
    var host = colonIndex >= 0 ? hostPort.substring(0, colonIndex) : hostPort;
    return host.toLowerCase();
}

function _shouldSendAuth(url) {
    var host = _extractHost(url);
    return host === "api.mangadex.org" || host === "auth.mangadex.org";
}

function _parseRetryAfterSeconds(headerValue) {
    var raw = String(headerValue || "").trim();
    if (raw === "") {
        return 0;
    }

    var numeric = Number(raw);
    if (!isNaN(numeric) && numeric > 0) {
        return Math.max(1, Math.ceil(numeric));
    }

    var parsedDateMs = Date.parse(raw);
    if (!isNaN(parsedDateMs)) {
        var deltaMs = parsedDateMs - Date.now();
        if (deltaMs > 0) {
            return Math.max(1, Math.ceil(deltaMs / 1000));
        }
    }

    return 0;
}

function _errorFromResponse(xhr, bodyObj) {
    var message = "HTTP " + xhr.status;
    if (bodyObj && bodyObj.errors && _isArray(bodyObj.errors) && bodyObj.errors.length > 0) {
        var firstError = bodyObj.errors[0];
        if (firstError.detail) {
            message = firstError.detail;
        } else if (firstError.title) {
            message = firstError.title;
        }
    } else if (bodyObj && bodyObj.message) {
        message = bodyObj.message;
    }

    var retryAfterRaw = xhr.getResponseHeader("Retry-After")
        || xhr.getResponseHeader("X-RateLimit-Retry-After")
        || "";
    var retryAfterSeconds = _parseRetryAfterSeconds(retryAfterRaw);

    return {
        status: xhr.status,
        message: message,
        retryAfter: retryAfterSeconds > 0 ? String(retryAfterSeconds) : "",
        retryAfterRaw: retryAfterRaw,
        retryAfterSeconds: retryAfterSeconds,
        retryAfterMs: retryAfterSeconds > 0 ? retryAfterSeconds * 1000 : 0,
        rateLimitLimit: xhr.getResponseHeader("X-RateLimit-Limit") || "",
        rateLimitRemaining: xhr.getResponseHeader("X-RateLimit-Remaining") || "",
        raw: bodyObj
    };
}

function _isRetriableStatus(statusValue) {
    var status = Number(statusValue || 0);
    return status === 0
        || status === 408
        || status === 425
        || status === 429
        || status === 500
        || status === 502
        || status === 503
        || status === 504;
}

function _computeBackoffMs(errorObj, retryCount, baseDelayMs) {
    var retryAfterMs = Number(errorObj && errorObj.retryAfterMs ? errorObj.retryAfterMs : 0);
    if (retryAfterMs > 0) {
        return Math.min(MAX_BACKOFF_MS, retryAfterMs);
    }

    var exponent = Math.pow(2, Math.max(0, retryCount));
    var delayMs = Math.round(baseDelayMs * exponent);
    if (Number(errorObj && errorObj.status) === 429) {
        delayMs = Math.max(delayMs, 1000);
    }

    return Math.max(0, Math.min(MAX_BACKOFF_MS, delayMs));
}

function _requestId() {
    _requestSequence += 1;
    return "mdx-" + String(_requestSequence);
}

function _reservePacingDelay(pacingMs) {
    var now = Date.now();
    var minSpacing = Math.max(0, Number(pacingMs || 0));
    if (minSpacing <= 0) {
        _lastRequestStartMs = now;
        return 0;
    }

    var nextAllowed = _lastRequestStartMs + minSpacing;
    var delayMs = Math.max(0, nextAllowed - now);
    _lastRequestStartMs = now + delayMs;
    return delayMs;
}

function _schedule(delayMs, timerHost, callback) {
    var waitMs = Math.max(0, Number(delayMs || 0));
    if (waitMs <= 0) {
        callback();
        return;
    }

    if (timerHost && typeof Qt !== "undefined" && typeof Qt.createQmlObject === "function") {
        try {
            var timer = Qt.createQmlObject("import QtQuick; Timer { repeat: false }", timerHost, "MangaDexApiDelay");
            timer.interval = Math.round(waitMs);
            timer.triggered.connect(function() {
                timer.destroy();
                callback();
            });
            timer.start();
            return;
        } catch (e) {
            _diag("warn", "api.schedule.fallback", {
                delayMs: waitMs,
                exception: String(e)
            }, "Falling back to immediate scheduling due to Timer creation failure");
        }
    }

    callback();
}

function _mergeRequestOptions(baseOptions, requestOptions, endpointContext) {
    var merged = {};
    var key;

    for (key in baseOptions) {
        if (baseOptions.hasOwnProperty(key)) {
            merged[key] = baseOptions[key];
        }
    }

    if (requestOptions && typeof requestOptions === "object") {
        if (requestOptions.timeoutMs !== undefined) {
            merged.timeoutMs = requestOptions.timeoutMs;
        }
        if (requestOptions.timerHost !== undefined) {
            merged.timerHost = requestOptions.timerHost;
        }
        if (requestOptions.maxRetries !== undefined) {
            merged.maxRetries = requestOptions.maxRetries;
        }
        if (requestOptions.backoffBaseMs !== undefined) {
            merged.backoffBaseMs = requestOptions.backoffBaseMs;
        }
        if (requestOptions.pacingMs !== undefined) {
            merged.pacingMs = requestOptions.pacingMs;
        }
        if (requestOptions.requestId !== undefined) {
            merged.requestId = requestOptions.requestId;
        }
    }

    merged.context = _diagChild(
        requestOptions && requestOptions.context ? requestOptions.context : {},
        endpointContext || {});

    return merged;
}

function requestJson(options, onSuccess, onError) {
    var method = String(options.method || "GET").toUpperCase();
    var path = options.path || "/";
    var baseUrl = options.baseUrl || API_BASE;
    var query = _encodeQuery(options.query || {});
    var url = baseUrl + path + (query ? "?" + query : "");

    if (options.requireAuth && (!options.accessToken || String(options.accessToken).trim() === "")) {
        onError({
            status: 401,
            message: "Authentication required",
            path: path,
            method: method,
            requestId: options.requestId || ""
        });
        return;
    }

    var timeoutMs = _safeNumber(options.timeoutMs, DEFAULT_TIMEOUT_MS, 1000, 120000);
    var pacingMs = _safeNumber(options.pacingMs, DEFAULT_PACING_MS, 0, 3000);
    var maxRetries = _safeNumber(options.maxRetries, DEFAULT_MAX_RETRIES, 0, 5);
    var backoffBaseMs = _safeNumber(options.backoffBaseMs, DEFAULT_BACKOFF_BASE_MS, 100, 10000);
    var timerHost = options.timerHost || null;
    var requestId = options.requestId || _requestId();

    var retryCount = 0;
    var finished = false;

    function finalizeError(errorObj) {
        if (finished) {
            return;
        }

        var enriched = errorObj || {
            status: 0,
            message: "Unknown request error"
        };
        enriched.path = path;
        enriched.method = method;
        enriched.requestId = requestId;
        enriched.attempt = retryCount + 1;

        _diag("error", "api.request.failure", _diagChild(options.context || {}, {
            requestId: requestId,
            method: method,
            path: path,
            status: Number(enriched.status || 0),
            retriesUsed: retryCount,
            message: enriched.message || ""
        }), "API request failed");

        finished = true;
        onError(enriched);
    }

    function finalizeSuccess(payload, statusCode, durationMs) {
        if (finished) {
            return;
        }

        _diag("info", "api.request.success", _diagChild(options.context || {}, {
            requestId: requestId,
            method: method,
            path: path,
            status: Number(statusCode || 0),
            retriesUsed: retryCount,
            durationMs: Math.round(durationMs || 0)
        }), "API request completed");

        finished = true;
        onSuccess(payload || {});
    }

    function executeRequest(initialDelayMs, trigger) {
        if (finished) {
            return;
        }

        var pacingDelayMs = _reservePacingDelay(pacingMs);
        var totalDelayMs = Math.max(0, Number(initialDelayMs || 0)) + pacingDelayMs;

        if (totalDelayMs > 0) {
            _diag("debug", "api.request.delay", _diagChild(options.context || {}, {
                requestId: requestId,
                method: method,
                path: path,
                trigger: trigger || "initial",
                delayMs: Math.round(totalDelayMs),
                pacingDelayMs: Math.round(pacingDelayMs)
            }), "Delaying API request due to pacing or backoff");
        }

        _schedule(totalDelayMs, timerHost, function() {
            if (finished) {
                return;
            }

            var attemptNumber = retryCount + 1;
            var startedAtMs = Date.now();
            var xhr = new XMLHttpRequest();
            xhr.timeout = timeoutMs;

            var requestCompleted = false;

            function cleanup() {
                requestCompleted = true;
            }

            function maybeRetry(errorObj) {
                var enrichedError = errorObj || {
                    status: 0,
                    message: "Request failed"
                };
                enrichedError.path = path;
                enrichedError.method = method;
                enrichedError.requestId = requestId;
                enrichedError.attempt = attemptNumber;

                var shouldRetry = _isRetriableStatus(enrichedError.status) && retryCount < maxRetries;
                if (!shouldRetry) {
                    finalizeError(enrichedError);
                    return;
                }

                var nextDelayMs = _computeBackoffMs(enrichedError, retryCount, backoffBaseMs);
                _diag("warn", "api.request.retry", _diagChild(options.context || {}, {
                    requestId: requestId,
                    method: method,
                    path: path,
                    status: Number(enrichedError.status || 0),
                    retryCount: retryCount + 1,
                    maxRetries: maxRetries,
                    delayMs: Math.round(nextDelayMs)
                }), "Retrying API request after retriable failure");

                retryCount += 1;
                executeRequest(nextDelayMs, "retry");
            }

            try {
                xhr.open(method, url);
            } catch (openError) {
                cleanup();
                maybeRetry({
                    status: 0,
                    message: "Failed to initialize request: " + openError
                });
                return;
            }

            if (options.accessToken && _shouldSendAuth(url)) {
                xhr.setRequestHeader("Authorization", "Bearer " + options.accessToken);
            }

            if (method !== "GET" && method !== "HEAD") {
                xhr.setRequestHeader("Content-Type", "application/json");
            }

            _diag("debug", "api.request.start", _diagChild(options.context || {}, {
                requestId: requestId,
                method: method,
                path: path,
                attempt: attemptNumber,
                timeoutMs: timeoutMs
            }), "Sending API request");

            xhr.onreadystatechange = function() {
                if (xhr.readyState !== 4) {
                    return;
                }

                if (requestCompleted || finished) {
                    return;
                }
                cleanup();

                var bodyObj = null;
                if (xhr.responseText && xhr.responseText.trim() !== "") {
                    try {
                        bodyObj = JSON.parse(xhr.responseText);
                    } catch (parseError) {
                        if (xhr.status >= 200 && xhr.status < 300) {
                            maybeRetry({
                                status: xhr.status,
                                message: "Invalid JSON response",
                                raw: xhr.responseText
                            });
                            return;
                        }
                    }
                }

                if (xhr.status >= 200 && xhr.status < 300) {
                    finalizeSuccess(bodyObj || {}, xhr.status, Date.now() - startedAtMs);
                    return;
                }

                maybeRetry(_errorFromResponse(xhr, bodyObj));
            };

            xhr.onerror = function() {
                if (requestCompleted || finished) {
                    return;
                }
                cleanup();
                maybeRetry({
                    status: 0,
                    message: "Network error while contacting api.mangadex.org"
                });
            };

            xhr.ontimeout = function() {
                if (requestCompleted || finished) {
                    return;
                }
                cleanup();
                maybeRetry({
                    status: 0,
                    message: "Request timed out while contacting api.mangadex.org"
                });
            };

            if (options.body) {
                xhr.send(JSON.stringify(options.body));
            } else {
                xhr.send();
            }
        });
    }

    executeRequest(0, "initial");
}

function searchManga(queryText, offset, limit, filters, accessToken, onSuccess, onError, requestOptions) {
    var safeLimit = _safeNumber(limit, 20, 1, SEARCH_LIMIT_MAX);
    var safeOffset = _normalizeOffset(offset);

    var params = {
        limit: safeLimit,
        offset: safeOffset,
        "order[latestUploadedChapter]": "desc",
        "includes[]": ["cover_art", "author", "artist"]
    };

    if (queryText && queryText.trim() !== "") {
        params.title = queryText.trim();
    }

    if (filters && _isArray(filters.translatedLanguages) && filters.translatedLanguages.length > 0) {
        params["availableTranslatedLanguage[]"] = filters.translatedLanguages;
    }

    if (filters && _isArray(filters.contentRatings) && filters.contentRatings.length > 0) {
        params["contentRating[]"] = filters.contentRatings;
    }

    requestJson(_mergeRequestOptions({
        path: "/manga",
        query: params,
        accessToken: accessToken
    }, requestOptions, {
        endpoint: "search-manga",
        limit: safeLimit,
        offset: safeOffset
    }), onSuccess, onError);
}

function getMangaById(mangaId, accessToken, onSuccess, onError, requestOptions) {
    requestJson(_mergeRequestOptions({
        path: "/manga/" + encodeURIComponent(mangaId),
        query: {
            "includes[]": ["cover_art", "author", "artist", "tag"]
        },
        accessToken: accessToken
    }, requestOptions, {
        endpoint: "manga-by-id",
        mangaId: mangaId
    }), onSuccess, onError);
}

function getMangaFeed(mangaId, offset, limit, filters, accessToken, onSuccess, onError, requestOptions) {
    var safeLimit = _safeNumber(limit, 100, 1, FEED_LIMIT_MAX);
    var safeOffset = _normalizeOffset(offset);

    var params = {
        limit: safeLimit,
        offset: safeOffset,
        "order[chapter]": "asc",
        "order[volume]": "asc",
        "includes[]": ["scanlation_group", "user"]
    };

    if (filters && _isArray(filters.translatedLanguages) && filters.translatedLanguages.length > 0) {
        params["translatedLanguage[]"] = filters.translatedLanguages;
    }

    if (filters && _isArray(filters.contentRatings) && filters.contentRatings.length > 0) {
        params["contentRating[]"] = filters.contentRatings;
    }

    requestJson(_mergeRequestOptions({
        path: "/manga/" + encodeURIComponent(mangaId) + "/feed",
        query: params,
        accessToken: accessToken
    }, requestOptions, {
        endpoint: "manga-feed",
        mangaId: mangaId,
        limit: safeLimit,
        offset: safeOffset
    }), onSuccess, onError);
}

function getAtHomeServer(chapterId, forcePort443, onSuccess, onError, requestOptions) {
    requestJson(_mergeRequestOptions({
        path: "/at-home/server/" + encodeURIComponent(chapterId),
        query: {
            forcePort443: forcePort443 ? "true" : "false"
        }
    }, requestOptions, {
        endpoint: "at-home-server",
        chapterId: chapterId
    }), onSuccess, onError);
}

function getFollowedFeed(offset, limit, filters, accessToken, onSuccess, onError, requestOptions) {
    var safeLimit = _safeNumber(limit, 100, 1, FEED_LIMIT_MAX);
    var safeOffset = _normalizeOffset(offset);

    var params = {
        limit: safeLimit,
        offset: safeOffset,
        "order[publishAt]": "desc",
        "includes[]": ["manga", "scanlation_group", "user"]
    };

    if (filters && _isArray(filters.translatedLanguages) && filters.translatedLanguages.length > 0) {
        params["translatedLanguage[]"] = filters.translatedLanguages;
    }

    if (filters && _isArray(filters.contentRatings) && filters.contentRatings.length > 0) {
        params["contentRating[]"] = filters.contentRatings;
    }

    requestJson(_mergeRequestOptions({
        path: "/user/follows/manga/feed",
        query: params,
        accessToken: accessToken,
        requireAuth: true
    }, requestOptions, {
        endpoint: "followed-feed",
        limit: safeLimit,
        offset: safeOffset
    }), onSuccess, onError);
}

function getMangaReadMarkers(mangaId, accessToken, onSuccess, onError, requestOptions) {
    requestJson(_mergeRequestOptions({
        path: "/manga/" + encodeURIComponent(mangaId) + "/read",
        accessToken: accessToken,
        requireAuth: true
    }, requestOptions, {
        endpoint: "read-markers-get",
        mangaId: mangaId
    }), onSuccess, onError);
}

function updateReadMarkers(mangaId, chapterIdsRead, chapterIdsUnread, accessToken, onSuccess, onError, requestOptions) {
    requestJson(_mergeRequestOptions({
        method: "POST",
        path: "/manga/" + encodeURIComponent(mangaId) + "/read",
        body: {
            chapterIdsRead: chapterIdsRead || [],
            chapterIdsUnread: chapterIdsUnread || []
        },
        accessToken: accessToken,
        requireAuth: true
    }, requestOptions, {
        endpoint: "read-markers-update",
        mangaId: mangaId,
        readCount: _isArray(chapterIdsRead) ? chapterIdsRead.length : 0,
        unreadCount: _isArray(chapterIdsUnread) ? chapterIdsUnread.length : 0
    }), onSuccess, onError);
}

function getMangaStatus(mangaId, accessToken, onSuccess, onError, requestOptions) {
    requestJson(_mergeRequestOptions({
        path: "/manga/" + encodeURIComponent(mangaId) + "/status",
        accessToken: accessToken,
        requireAuth: true
    }, requestOptions, {
        endpoint: "manga-status-get",
        mangaId: mangaId
    }), onSuccess, onError);
}

function setMangaStatus(mangaId, status, accessToken, onSuccess, onError, requestOptions) {
    requestJson(_mergeRequestOptions({
        method: "POST",
        path: "/manga/" + encodeURIComponent(mangaId) + "/status",
        body: {
            status: status === "" ? null : status
        },
        accessToken: accessToken,
        requireAuth: true
    }, requestOptions, {
        endpoint: "manga-status-set",
        mangaId: mangaId,
        status: status
    }), onSuccess, onError);
}
