// providers.js — Entry point for AnimeReloaded JS providers
// Loaded by Main.qml via: import "js/providers.js" as Providers
// Uses Qt.include() to load sibling files into shared scope.
// NOTE: No .pragma library — Qt.include() requires a non-isolated scope
// so that included declarations merge correctly.

// Qt.include loads sibling files — their declarations merge into this scope.
// Order matters: crypto-helper first (provides CryptoHelper IIFE),
// then allanime/anilist (core providers), mapping-cache (uses allanime for mapper),
// then mal-provider (uses anilist for MAL↔AniList ID lookups).
Qt.include("crypto-helper.js");
Qt.include("allanime-provider.js");
Qt.include("anilist-provider.js");
Qt.include("mapping-cache.js");
Qt.include("mal-provider.js");

// --- Public dispatcher API ---
// Mirrors provider_cli.py command structure.
// All methods are async: function(args..., callback) where callback(errorString, result)
// NOTE: Using top-level function declarations (not var Providers = {}) so QML
// import "js/providers.js" as Providers exposes them as Providers.metadata(), etc.

// --- Crypto cache management (called from Main.qml) ---

function initCryptoCache(cacheDir) {
    CryptoHelper.init(cacheDir);
}

function ensureCryptoLoaded() {
    CryptoHelper.ensureLoaded();
}

function hasPendingForgeCache() {
    return CryptoHelper.needsCacheWrite();
}

function getForgeCdnUrl() {
    return CryptoHelper.cdnUrl();
}

function markForgeCacheWritten() {
    CryptoHelper.markCacheWritten();
}

// --- Metadata provider commands ---

function metadata(providerId, command, args, callback) {
    providerId = (providerId || "").trim();
    command = (command || "").trim();

    if (command === "genres") {
        if (providerId === "anilist") {
            _anilistListGenres(callback);
        } else if (providerId === "allanime") {
            callback(null, _AA_GENRES || []);
        } else {
            callback("Unknown metadata provider: " + providerId);
        }
        return;
    }

    if (command === "popular") {
        var popPage = args.page || 1;
        var popMode = args.mode || "sub";
        var popGenre = args.genre || null;
        var popStreamProvider = args.streamProvider || providerId;
        if (providerId === "anilist") {
            _anilistPopular(popPage, popMode, popGenre, popStreamProvider, callback);
        } else if (providerId === "allanime") {
            _allanimePopular(popPage, popMode, popGenre, callback);
        } else {
            callback("Unknown metadata provider: " + providerId);
        }
        return;
    }

    if (command === "recent" || command === "latest") {
        var recPage = args.page || 1;
        var recMode = args.mode || "sub";
        var recCountry = args.country || "ALL";
        var recStreamProvider = args.streamProvider || providerId;
        if (providerId === "anilist") {
            _anilistRecent(recPage, recMode, recCountry, recStreamProvider, callback);
        } else if (providerId === "allanime") {
            _allanimeRecent(recPage, recMode, recCountry, callback);
        } else {
            callback("Unknown metadata provider: " + providerId);
        }
        return;
    }

    if (command === "search") {
        var searchQuery = args.query || "";
        var searchMode = args.mode || "sub";
        var searchPage = args.page || 1;
        var searchGenre = args.genre || null;
        var searchStreamProvider = args.streamProvider || providerId;
        if (providerId === "anilist") {
            _anilistSearch(searchQuery, searchMode, searchPage, searchGenre, searchStreamProvider, callback);
        } else if (providerId === "allanime") {
            _allanimeSearchShows(searchQuery, searchMode, searchPage, callback);
        } else {
            callback("Unknown metadata provider: " + providerId);
        }
        return;
    }

    if (command === "episodes") {
        var epShowId = args.showId || "";
        var epMode = args.mode || "sub";
        var epStreamProvider = args.streamProvider || providerId;
        if (providerId === "anilist") {
            _anilistEpisodes(epShowId, epMode, epStreamProvider, callback);
        } else if (providerId === "allanime") {
            _allanimeEpisodes(epShowId, epMode, epStreamProvider, callback);
        } else {
            callback("Unknown metadata provider: " + providerId);
        }
        return;
    }

    if (command === "feed") {
        var feedEntries = args.libraryEntries || [];
        var feedMode = args.mode || "sub";
        var feedStreamProvider = args.streamProvider || providerId;
        if (providerId === "anilist") {
            _anilistFeed(feedEntries, feedMode, feedStreamProvider, callback);
        } else if (providerId === "allanime") {
            _allanimeFeed(feedEntries, feedMode, callback);
        } else {
            callback("Unknown metadata provider: " + providerId);
        }
        return;
    }

    callback("Unknown metadata command: " + command);
}

// --- Stream provider commands ---

function stream(providerId, command, args, callback) {
    providerId = (providerId || "").trim();
    command = (command || "").trim();

    if (command !== "resolve") {
        callback("Unknown stream command: " + command);
        return;
    }

    var showId = args.showId || "";
    var episodeNumber = args.episodeNumber || "";
    var mode = args.mode || "sub";
    var mirrorPref = args.mirrorPref || "auto";
    var qualityPref = args.qualityPref || "best";
    var metadataProviderId = args.metadataProviderId || providerId;
    var title = args.title || "";

    if (providerId === "allanime") {
        _allanimeResolveStream(showId, episodeNumber, mode, mirrorPref, qualityPref, metadataProviderId, callback, title);
    } else {
        callback("Unknown stream provider: " + providerId);
    }
}

// --- Sync provider commands ---

function sync(providerId, command, args, callback) {
    providerId = (providerId || "").trim();
    command = (command || "").trim();

    if (providerId !== "myanimelist") {
        callback("Unknown sync provider: " + providerId);
        return;
    }

    if (command === "auth-url") {
        _malBuildAuthUrl(args.config || {}, callback);
        return;
    }

    if (command === "listen-exchange") {
        _malAwaitBrowserLogin(args.config || {}, args.timeout || 240, callback);
        return;
    }

    if (command === "refresh") {
        _malRefreshSession(args.config || {}, callback);
        return;
    }

    if (command === "delete-entry") {
        _malRemoveAnimeEntry(args.config || {}, args.malId || "", args.title || "", callback);
        return;
    }

    if (command === "push") {
        _malPushLibrary(args.config || {}, args.libraryEntries || [], callback);
        return;
    }

    if (command === "pull") {
        _malPullLibrary(args.config || {}, args.libraryEntries || [], callback);
        return;
    }

    callback("Unknown sync command: " + command);
}
