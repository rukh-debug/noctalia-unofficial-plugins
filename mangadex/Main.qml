import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import "AuthService.js" as AuthService
import "MangaDexApi.js" as MangaDexApi
import "ReaderService.js" as ReaderService
import "Diagnostics.js" as Diagnostics
import "api/PaginationRules.js" as PaginationRules
import "core/ReaderRecovery.js" as ReaderRecovery
import "reader/PageSlotModel.js" as PageSlotModel
import "utils/SearchMerge.js" as SearchMerge

Item {
  id: root

  property var pluginApi: null

  // --------------------
  // Persistent state/cache
  // --------------------
  readonly property string cacheDir: typeof Settings !== "undefined" && Settings.cacheDir ? Settings.cacheDir + "plugins/mangadex/" : ""
  readonly property string stateCachePath: cacheDir + "state.json"

  property string pendingMangaId: ""
  property string pendingChapterId: ""

  // --------------------
  // Settings accessors
  // --------------------
  readonly property string configuredClientId: pluginApi?.pluginSettings?.auth?.clientId ?? pluginApi?.manifest?.metadata?.defaultSettings?.auth?.clientId ?? ""
  readonly property string configuredClientSecret: pluginApi?.pluginSettings?.auth?.clientSecret ?? pluginApi?.manifest?.metadata?.defaultSettings?.auth?.clientSecret ?? ""
  readonly property string configuredIdentity: pluginApi?.pluginSettings?.auth?.identity ?? pluginApi?.pluginSettings?.auth?.username ?? pluginApi?.manifest?.metadata?.defaultSettings?.auth?.identity ?? pluginApi?.manifest?.metadata?.defaultSettings?.auth?.username ?? ""
  readonly property bool rememberSession: pluginApi?.pluginSettings?.auth?.rememberSession ?? pluginApi?.manifest?.metadata?.defaultSettings?.auth?.rememberSession ?? true

  readonly property string preferredLanguage: pluginApi?.pluginSettings?.reader?.preferredLanguage ?? pluginApi?.manifest?.metadata?.defaultSettings?.reader?.preferredLanguage ?? "en"
  readonly property string defaultQualityMode: pluginApi?.pluginSettings?.reader?.quality ?? pluginApi?.manifest?.metadata?.defaultSettings?.reader?.quality ?? "data-saver"
  readonly property var translatedLanguages: normalizeStringArray(
      pluginApi?.pluginSettings?.reader?.translatedLanguages,
      pluginApi?.manifest?.metadata?.defaultSettings?.reader?.translatedLanguages,
      ["en"])
  readonly property var contentRatings: normalizeStringArray(
      pluginApi?.pluginSettings?.reader?.contentRatings,
      pluginApi?.manifest?.metadata?.defaultSettings?.reader?.contentRatings,
      ["safe", "suggestive", "erotica"])
    readonly property string diagnosticsModeSetting: normalizeDiagnosticsMode(
      pluginApi?.pluginSettings?.diagnostics?.loggingMode,
      pluginApi?.manifest?.metadata?.defaultSettings?.diagnostics?.loggingMode,
      "normal")

    readonly property string configuredPanelPosition: pluginApi?.pluginSettings?.panelPosition ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelPosition ?? "right"
    readonly property string panelSide: normalizePanelSide(configuredPanelPosition)
    readonly property int panelWidthMin: Math.max(560,
      Number(pluginApi?.pluginSettings?.panelWidthMin ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelWidthMin ?? 760))
    readonly property int panelWidthMax: Math.max(panelWidthMin,
      Number(pluginApi?.pluginSettings?.panelWidthMax ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelWidthMax ?? 1800))
    readonly property int panelWidthSetting: Number(pluginApi?.pluginSettings?.panelWidth ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelWidth ?? 1120)
    readonly property real panelWidthPx: clampPanelWidth(panelWidthSetting) * Style.uiScaleRatio
    readonly property real panelHeightPx: Math.max(480,
      Number(pluginApi?.pluginSettings?.panelHeight ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelHeight ?? 760)) * Style.uiScaleRatio
    readonly property bool readerMinimalControls: pluginApi?.pluginSettings?.reader?.minimalControls ?? pluginApi?.manifest?.metadata?.defaultSettings?.reader?.minimalControls ?? true
    readonly property bool readerUtilityCollapsed: pluginApi?.pluginSettings?.reader?.utilityCollapsed ?? pluginApi?.manifest?.metadata?.defaultSettings?.reader?.utilityCollapsed ?? false
    readonly property int pageCacheMaxEntries: Math.max(20,
      Number(pluginApi?.pluginSettings?.reader?.pageCacheMaxEntries
          ?? pluginApi?.manifest?.metadata?.defaultSettings?.reader?.pageCacheMaxEntries
          ?? 80))
    readonly property int pageCachePerChapterMaxEntries: Math.max(5,
      Number(pluginApi?.pluginSettings?.reader?.pageCachePerChapterMaxEntries
          ?? pluginApi?.manifest?.metadata?.defaultSettings?.reader?.pageCachePerChapterMaxEntries
          ?? 30))

  readonly property int searchPageSize: Math.max(1, Math.min(100,
      Number(pluginApi?.pluginSettings?.network?.searchPageSize ?? pluginApi?.manifest?.metadata?.defaultSettings?.network?.searchPageSize ?? 20)))
  readonly property int cooldownSecondsOn429: Math.max(1,
      Number(pluginApi?.pluginSettings?.network?.cooldownSecondsOn429 ?? pluginApi?.manifest?.metadata?.defaultSettings?.network?.cooldownSecondsOn429 ?? 8))
    readonly property int requestPacingMs: Math.max(0,
      Number(pluginApi?.pluginSettings?.network?.requestPacingMs ?? pluginApi?.manifest?.metadata?.defaultSettings?.network?.requestPacingMs ?? 250))
    readonly property int maxRetryAttempts: Math.max(0,
      Number(pluginApi?.pluginSettings?.network?.maxRetryAttempts ?? pluginApi?.manifest?.metadata?.defaultSettings?.network?.maxRetryAttempts ?? 2))
    readonly property int retryBaseDelayMs: Math.max(100,
      Number(pluginApi?.pluginSettings?.network?.retryBaseDelayMs ?? pluginApi?.manifest?.metadata?.defaultSettings?.network?.retryBaseDelayMs ?? 400))

  // --------------------
  // Auth/session state
  // --------------------
  property string accessToken: ""
  property string refreshToken: ""
  property int accessTokenExpiresAt: 0
  property bool authBusy: false
  property string authError: ""

  readonly property bool hasAccessToken: accessToken !== ""
  readonly property bool hasRefreshToken: refreshToken !== ""
  readonly property bool isAuthenticated: hasAccessToken || hasRefreshToken

  // --------------------
  // Discovery state
  // --------------------
  property string searchQuery: ""
  property var searchResults: []
  property int searchOffset: 0
  property bool hasMoreSearch: true
  property bool isLoadingSearch: false
  property string searchError: ""

  // Chapter/feed state
  property bool showFollowedFeed: false
  property string followedError: ""
  property var selectedManga: null
  property var chapters: []
  property var mangaFeedCache: ({})
  property bool isLoadingChapters: false
  property string chapterError: ""

  // Reader state
  property var currentChapter: null
  property var atHomeMetadata: null
  property var pageUrls: []
  property bool isLoadingPages: false
  property string readerError: ""
  property bool chapterRetryUsed: false
  property bool chapterQualityFallbackUsed: false
  property bool chapterTargetedRetryUsed: false
  property bool chapterRecoveryInProgress: false
  property int chapterLoadToken: 0
  property string chapterLoadState: "idle"
  property string qualityMode: defaultQualityMode
  property var readerViewportAnchor: ({
    chapterId: "",
    pageIdentity: "",
    pageIndex: 0,
    offsetRatio: 0,
    scrollY: 0,
    timestampMs: 0
  })
  property int readerRenderEpoch: 0
  property string lastReaderRecoveryReason: ""
  property var pageImageCacheEntries: ({})
  property var pageImageCacheLru: []
  property int pageImageCacheRevision: 0
  property var pageSlotStates: ({})
  property int pageSlotRevision: 0

  // Sync state
  property var readMarkers: ({})
  property string mangaReadingStatus: ""

  // Rate-limit guard
  property int cooldownUntil: 0

  // Save-state debounce
  property bool saveStateQueued: false

  // --------------------
  // Lifecycle
  // --------------------
  Component.onCompleted: {
    ensureCacheDir();
    initializeSettingsContainers();
    applyDiagnosticsMode(diagnosticsModeSetting);
    Diagnostics.info("plugin.initialized", {
      loggingMode: Diagnostics.getMode(),
      requestPacingMs: requestPacingMs,
      maxRetryAttempts: maxRetryAttempts,
      retryBaseDelayMs: retryBaseDelayMs
    }, "Plugin initialized");
    restoreSessionFromSettings();
  }

  onDiagnosticsModeSettingChanged: {
    applyDiagnosticsMode(diagnosticsModeSetting);
  }

  onQualityModeChanged: {
    if (atHomeMetadata) {
      pageUrls = buildRuntimePageEntries(atHomeMetadata, qualityMode);
      hydratePageSlotStates("quality_mode_changed");
      bumpReaderRenderEpoch("page_model_changed", false);
    }
    Diagnostics.debug("reader.quality.changed", {
      qualityMode: qualityMode,
      chapterId: currentChapter?.id || ""
    }, "Reader quality mode updated");
    saveState();
  }

  // --------------------
  // IPC
  // --------------------
  IpcHandler {
    target: "plugin:mangadex"

    function toggle() {
      if (!pluginApi) {
        return;
      }
      pluginApi.withCurrentScreen(function(screen) {
        pluginApi.togglePanel(screen);
      });
    }

    function open() {
      if (!pluginApi) {
        return;
      }
      pluginApi.withCurrentScreen(function(screen) {
        pluginApi.openPanel(screen);
      });
    }

    function search(query: string) {
      if (!pluginApi) {
        return;
      }
      root.searchQuery = query || "";
      root.searchManga(true);
      pluginApi.withCurrentScreen(function(screen) {
        pluginApi.openPanel(screen);
      });
    }

    function openManga(mangaId: string) {
      if (!pluginApi || !mangaId) {
        return;
      }
      selectMangaById(mangaId);
      pluginApi.withCurrentScreen(function(screen) {
        pluginApi.openPanel(screen);
      });
    }
  }

  // --------------------
  // Cache file
  // --------------------
  FileView {
    id: stateCacheFile
    path: root.stateCachePath
    watchChanges: false

    onLoaded: {
      loadStateFromCache();
    }

    onLoadFailed: function(error) {
      if (error === 2) {
        Logger.d("MangaDex", "No cache file found");
      } else {
        Logger.e("MangaDex", "Failed to load state cache: " + error);
      }
    }
  }

  Timer {
    id: saveStateTimer
    interval: 500
    onTriggered: performSaveState()
  }

  // --------------------
  // Helper utilities
  // --------------------
  function normalizeStringArray(primaryValue, secondaryValue, fallbackValue) {
    var source = primaryValue;
    if (!source || source.length === 0) {
      source = secondaryValue;
    }

    if (Object.prototype.toString.call(source) !== "[object Array]") {
      source = fallbackValue;
    }

    if (Object.prototype.toString.call(source) !== "[object Array]") {
      return [];
    }

    var out = [];
    for (var i = 0; i < source.length; i++) {
      if (source[i] !== undefined && source[i] !== null && String(source[i]).trim() !== "") {
        out.push(String(source[i]).trim());
      }
    }
    return out;
  }

  function normalizePanelSide(sideValue) {
    var normalized = String(sideValue || "").toLowerCase().trim();
    return normalized === "left" ? "left" : "right";
  }

  function clampUnitInterval(value) {
    var numeric = Number(value);
    if (isNaN(numeric)) {
      numeric = 0;
    }
    return Math.max(0, Math.min(1, numeric));
  }

  function cloneObject(sourceObj) {
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

  function cloneArray(sourceList) {
    if (Object.prototype.toString.call(sourceList) !== "[object Array]") {
      return [];
    }
    return sourceList.slice(0);
  }

  function bumpReaderRenderEpoch(reason, persistState) {
    var normalizedReason = ReaderRecovery.normalizeRecoveryReason(reason);
    if (!ReaderRecovery.shouldRemountForReason(normalizedReason)) {
      return;
    }

    readerRenderEpoch = ReaderRecovery.nextRenderEpoch(readerRenderEpoch);
    lastReaderRecoveryReason = normalizedReason;

    Diagnostics.warn("reader.render_epoch.bump", {
      chapterId: currentChapter?.id || "",
      reason: normalizedReason,
      renderEpoch: readerRenderEpoch
    }, "Incremented reader render epoch to force delegate remount");

    if (persistState) {
      saveState();
    }
  }

  function resetPageSlotStates(reason) {
    pageSlotStates = ({});
    pageSlotRevision = pageSlotRevision + 1;

    Diagnostics.debug("reader.page_slots.reset", {
      chapterId: currentChapter?.id || "",
      reason: String(reason || "reset")
    }, "Reset page slot states");
  }

  function hydratePageSlotStates(reason) {
    var chapterIdValue = String(currentChapter?.id || "").trim();
    if (chapterIdValue === "") {
      resetPageSlotStates(reason || "hydrate_without_chapter");
      return;
    }

    pageSlotStates = PageSlotModel.hydrateForEntries(pageSlotStates, chapterIdValue, pageUrls);
    pageSlotRevision = pageSlotRevision + 1;

    Diagnostics.debug("reader.page_slots.hydrate", {
      chapterId: chapterIdValue,
      reason: String(reason || "hydrate"),
      pageCount: pageUrls?.length || 0
    }, "Hydrated page slot states for current page model");
  }

  function pageSlotKeyForEntry(pageEntry, fallbackIndex) {
    return PageSlotModel.buildSlotKeyForEntry(currentChapter?.id || "", pageEntry, fallbackIndex);
  }

  function updatePageSlotState(pageEntry, fallbackIndex, statusValue, errorText, sourceUrl) {
    var slotKey = pageSlotKeyForEntry(pageEntry, fallbackIndex);
    if (slotKey === "") {
      return;
    }

    var previous = PageSlotModel.getSlotState(pageSlotStates, slotKey);
    var normalizedStatus = PageSlotModel.normalizeStatus(statusValue);
    var nextFailureCount = Number(previous.failureCount || 0);
    if (normalizedStatus === "error" || normalizedStatus === "stale") {
      nextFailureCount += 1;
    } else if (normalizedStatus === "ready") {
      nextFailureCount = 0;
    }

    pageSlotStates = PageSlotModel.setSlotState(pageSlotStates, slotKey, {
      status: normalizedStatus,
      failureCount: nextFailureCount,
      lastError: String(errorText || ""),
      source: String(sourceUrl || "")
    });
    pageSlotRevision = pageSlotRevision + 1;
  }

  function getPageSlotState(pageEntry, fallbackIndex) {
    var slotKey = pageSlotKeyForEntry(pageEntry, fallbackIndex);
    return PageSlotModel.getSlotState(pageSlotStates, slotKey);
  }

  function markPageSlotLoading(pageEntry, fallbackIndex, reasonText) {
    updatePageSlotState(pageEntry, fallbackIndex, "loading", reasonText || "", normalizePageEntry(pageEntry)?.source || "");
  }

  function markPageSlotReady(pageEntry, fallbackIndex, sourceUrl) {
    updatePageSlotState(pageEntry, fallbackIndex, "ready", "", sourceUrl || normalizePageEntry(pageEntry)?.source || "");
  }

  function markPageSlotError(pageEntry, fallbackIndex, reasonText, sourceUrl) {
    updatePageSlotState(pageEntry, fallbackIndex, "error", reasonText || "image-error", sourceUrl || normalizePageEntry(pageEntry)?.source || "");
  }

  function markPageSlotStale(pageEntry, fallbackIndex, reasonText, sourceUrl) {
    updatePageSlotState(pageEntry, fallbackIndex, "stale", reasonText || "stale", sourceUrl || normalizePageEntry(pageEntry)?.source || "");
  }

  function normalizeReaderAnchorData(anchorData, chapterIdFallback) {
    var source = anchorData && typeof anchorData === "object" ? anchorData : {};
    var chapterIdValue = String(source.chapterId || chapterIdFallback || "").trim();
    var pageIdentityValue = String(source.pageIdentity || "").trim();
    var pageIndexValue = Number(source.pageIndex);
    if (isNaN(pageIndexValue) || pageIndexValue < 0) {
      pageIndexValue = 0;
    }

    var scrollYValue = Number(source.scrollY);
    if (isNaN(scrollYValue) || scrollYValue < 0) {
      scrollYValue = 0;
    }

    return {
      chapterId: chapterIdValue,
      pageIdentity: pageIdentityValue,
      pageIndex: Math.round(pageIndexValue),
      offsetRatio: clampUnitInterval(source.offsetRatio),
      scrollY: scrollYValue,
      timestampMs: Number(source.timestampMs || Date.now())
    };
  }

  function updateReaderViewportAnchor(anchorData, persistToDisk) {
    var normalized = normalizeReaderAnchorData(anchorData, currentChapter?.id || "");
    if (!normalized.chapterId || normalized.chapterId === "") {
      return;
    }

    readerViewportAnchor = normalized;
    Diagnostics.debug("reader.anchor.updated", {
      chapterId: normalized.chapterId,
      pageIdentity: normalized.pageIdentity,
      pageIndex: normalized.pageIndex,
      offsetRatio: normalized.offsetRatio,
      scrollY: Math.round(normalized.scrollY)
    }, "Updated reader viewport anchor state");

    if (persistToDisk) {
      saveState();
    }
  }

  function getReaderViewportAnchor(chapterId) {
    var targetChapterId = String(chapterId || currentChapter?.id || "").trim();
    if (targetChapterId === "") {
      return null;
    }

    var normalized = normalizeReaderAnchorData(readerViewportAnchor, targetChapterId);
    if (normalized.chapterId !== targetChapterId) {
      return null;
    }
    return normalized;
  }

  function normalizeDiagnosticsMode(primaryValue, secondaryValue, fallbackValue) {
    var source = primaryValue;
    if (source === undefined || source === null || String(source).trim() === "") {
      source = secondaryValue;
    }

    var fallback = String(fallbackValue || "normal").toLowerCase().trim();
    if (fallback !== "off" && fallback !== "normal" && fallback !== "verbose") {
      fallback = "normal";
    }

    var normalized = String(source || fallback).toLowerCase().trim();
    if (normalized === "off" || normalized === "normal" || normalized === "verbose") {
      return normalized;
    }
    return fallback;
  }

  function diagnosticsSink(severity, text) {
    if (severity === "error") {
      Logger.e("MangaDex", text);
      return;
    }
    if (severity === "warn") {
      Logger.w("MangaDex", text);
      return;
    }
    if (severity === "debug") {
      Logger.d("MangaDex", text);
      return;
    }
    Logger.i("MangaDex", text);
  }

  function applyDiagnosticsMode(modeValue) {
    var normalized = normalizeDiagnosticsMode(modeValue, "normal", "normal");
    Diagnostics.configure({
      mode: normalized,
      sink: diagnosticsSink,
      prefix: "MangaDex"
    });

    if (typeof MangaDexApi.setDiagnostics === "function") {
      MangaDexApi.setDiagnostics(Diagnostics);
    }
    if (typeof ReaderService.setDiagnostics === "function") {
      ReaderService.setDiagnostics(Diagnostics);
    }
    if (typeof AuthService.setDiagnostics === "function") {
      AuthService.setDiagnostics(Diagnostics);
    }

    if (!pluginApi || !pluginApi.pluginSettings) {
      return;
    }

    initializeSettingsContainers();
    var persisted = normalizeDiagnosticsMode(pluginApi.pluginSettings?.diagnostics?.loggingMode, normalized, normalized);
    if (pluginApi.pluginSettings.diagnostics.loggingMode !== persisted) {
      pluginApi.pluginSettings.diagnostics.loggingMode = persisted;
      pluginApi.saveSettings();
    }
  }

  function createApiRequestOptions(operationName, extraContext) {
    return {
      timerHost: root,
      pacingMs: requestPacingMs,
      maxRetries: maxRetryAttempts,
      backoffBaseMs: retryBaseDelayMs,
      context: Diagnostics.childContext({
        operation: operationName || "request",
        chapterId: currentChapter?.id || "",
        selectedMangaId: selectedManga?.id || "",
        loggingMode: Diagnostics.getMode()
      }, extraContext || {})
    };
  }

  function clampPanelWidth(widthValue) {
    var numeric = Number(widthValue);
    if (isNaN(numeric) || numeric <= 0) {
      numeric = panelWidthMin;
    }
    return Math.max(panelWidthMin, Math.min(panelWidthMax, Math.round(numeric)));
  }

  function setReaderUtilityCollapsed(collapsedValue, persistValue) {
    if (!pluginApi || !pluginApi.pluginSettings || !pluginApi.pluginSettings.reader) {
      return;
    }

    pluginApi.pluginSettings.reader.utilityCollapsed = !!collapsedValue;
    if (persistValue) {
      pluginApi.saveSettings();
    }
  }

  function setReaderMinimalControls(minimalValue, persistValue) {
    if (!pluginApi || !pluginApi.pluginSettings || !pluginApi.pluginSettings.reader) {
      return;
    }

    pluginApi.pluginSettings.reader.minimalControls = !!minimalValue;
    if (persistValue) {
      pluginApi.saveSettings();
    }
  }

  function applyReaderLayoutPreferences(sideValue, widthValue, minimalControlsValue, utilityCollapsedValue, reopenPanel) {
    if (!pluginApi || !pluginApi.pluginSettings) {
      return;
    }

    initializeSettingsContainers();

    var touched = false;
    var nextSide = normalizePanelSide(sideValue);
    var nextWidth = clampPanelWidth(widthValue);

    if (pluginApi.pluginSettings.panelPosition !== nextSide) {
      pluginApi.pluginSettings.panelPosition = nextSide;
      touched = true;
    }

    if (Number(pluginApi.pluginSettings.panelWidth || 0) !== nextWidth) {
      pluginApi.pluginSettings.panelWidth = nextWidth;
      touched = true;
    }

    if (pluginApi.pluginSettings.panelDetached !== true) {
      pluginApi.pluginSettings.panelDetached = true;
      touched = true;
    }

    if (minimalControlsValue !== undefined && !!minimalControlsValue !== !!pluginApi.pluginSettings.reader.minimalControls) {
      pluginApi.pluginSettings.reader.minimalControls = !!minimalControlsValue;
      touched = true;
    }

    if (utilityCollapsedValue !== undefined && !!utilityCollapsedValue !== !!pluginApi.pluginSettings.reader.utilityCollapsed) {
      pluginApi.pluginSettings.reader.utilityCollapsed = !!utilityCollapsedValue;
      touched = true;
    }

    if (touched) {
      pluginApi.saveSettings();
    }

    if (reopenPanel && pluginApi.withCurrentScreen) {
      pluginApi.withCurrentScreen(function(screen) {
        pluginApi.openPanel(screen);
      });
    }
  }

  function nowSec() {
    return Math.floor(Date.now() / 1000);
  }

  function cooldownRemainingSec() {
    return Math.max(0, cooldownUntil - nowSec());
  }

  function isCoolingDown() {
    return cooldownRemainingSec() > 0;
  }

  function applyRateLimitIfNeeded(errorObj) {
    if (!errorObj || Number(errorObj.status) !== 429) {
      return;
    }

    var retryAfterSec = Number(errorObj.retryAfterSeconds || 0);
    if (retryAfterSec <= 0 && Number(errorObj.retryAfterMs || 0) > 0) {
      retryAfterSec = Math.max(1, Math.ceil(Number(errorObj.retryAfterMs || 0) / 1000));
    }

    if (retryAfterSec <= 0) {
      var retryAfterRaw = Number(errorObj.retryAfter || 0);
      if (retryAfterRaw > 1000000000) {
        retryAfterSec = Math.max(1, retryAfterRaw - nowSec());
      } else if (retryAfterRaw > 0) {
        retryAfterSec = retryAfterRaw;
      }
    }

    cooldownUntil = nowSec() + (retryAfterSec > 0 ? retryAfterSec : cooldownSecondsOn429);

    Diagnostics.warn("api.rate_limit.cooldown", {
      requestId: errorObj.requestId || "",
      endpoint: errorObj.path || "",
      retryAfterSec: retryAfterSec,
      cooldownUntil: cooldownUntil,
      remaining: errorObj.rateLimitRemaining || ""
    }, "Applied request cooldown");
  }

  function parseApiError(errorObj, fallback) {
    if (!errorObj) {
      return fallback;
    }

    if (Number(errorObj.status) === 429) {
      var remaining = Math.max(1, cooldownRemainingSec());
      if (errorObj.clientPacing === true) {
        return "Request pacing active. Retry in " + remaining + "s.";
      }
      return "Rate limited. Retry in " + remaining + "s.";
    }

    if (errorObj.userMessage && String(errorObj.userMessage).trim() !== "") {
      return errorObj.userMessage;
    }

    return errorObj.message || fallback;
  }

  function ensureCacheDir() {
    if (cacheDir && cacheDir !== "") {
      Quickshell.execDetached(["mkdir", "-p", cacheDir]);
    }
  }

  function initializeSettingsContainers() {
    if (!pluginApi || !pluginApi.pluginSettings) {
      return;
    }

    var touched = false;

    if (!pluginApi.pluginSettings.auth) {
      pluginApi.pluginSettings.auth = {};
      touched = true;
    }

    if (!pluginApi.pluginSettings.reader) {
      pluginApi.pluginSettings.reader = {};
      touched = true;
    }

    if (!pluginApi.pluginSettings.network) {
      pluginApi.pluginSettings.network = {};
      touched = true;
    }

    if (!pluginApi.pluginSettings.diagnostics) {
      pluginApi.pluginSettings.diagnostics = {};
      touched = true;
    }

    if (pluginApi.pluginSettings.panelDetached === undefined) {
      pluginApi.pluginSettings.panelDetached = true;
      touched = true;
    }

    if (pluginApi.pluginSettings.panelPosition === undefined) {
      pluginApi.pluginSettings.panelPosition = panelSide;
      touched = true;
    } else {
      var normalizedSide = normalizePanelSide(pluginApi.pluginSettings.panelPosition);
      if (normalizedSide !== pluginApi.pluginSettings.panelPosition) {
        pluginApi.pluginSettings.panelPosition = normalizedSide;
        touched = true;
      }
    }

    if (pluginApi.pluginSettings.panelWidthMin === undefined) {
      pluginApi.pluginSettings.panelWidthMin = panelWidthMin;
      touched = true;
    }

    if (pluginApi.pluginSettings.panelWidthMax === undefined) {
      pluginApi.pluginSettings.panelWidthMax = panelWidthMax;
      touched = true;
    }

    var normalizedWidth = clampPanelWidth(
        pluginApi.pluginSettings.panelWidth === undefined
            ? panelWidthSetting
            : pluginApi.pluginSettings.panelWidth);
    if (Number(pluginApi.pluginSettings.panelWidth || 0) !== normalizedWidth) {
      pluginApi.pluginSettings.panelWidth = normalizedWidth;
      touched = true;
    }

    if (!pluginApi.pluginSettings.reader.translatedLanguages) {
      pluginApi.pluginSettings.reader.translatedLanguages = translatedLanguages;
      touched = true;
    }

    if (!pluginApi.pluginSettings.reader.contentRatings) {
      pluginApi.pluginSettings.reader.contentRatings = contentRatings;
      touched = true;
    }

    if (pluginApi.pluginSettings.reader.quality === undefined) {
      pluginApi.pluginSettings.reader.quality = defaultQualityMode;
      touched = true;
    }

    if (pluginApi.pluginSettings.reader.minimalControls === undefined) {
      pluginApi.pluginSettings.reader.minimalControls = true;
      touched = true;
    }

    if (pluginApi.pluginSettings.reader.utilityCollapsed === undefined) {
      pluginApi.pluginSettings.reader.utilityCollapsed = false;
      touched = true;
    }

    if (pluginApi.pluginSettings.reader.pageCacheMaxEntries === undefined) {
      pluginApi.pluginSettings.reader.pageCacheMaxEntries = pageCacheMaxEntries;
      touched = true;
    }

    if (pluginApi.pluginSettings.reader.pageCachePerChapterMaxEntries === undefined) {
      pluginApi.pluginSettings.reader.pageCachePerChapterMaxEntries = pageCachePerChapterMaxEntries;
      touched = true;
    }

    if (pluginApi.pluginSettings.network.requestPacingMs === undefined) {
      pluginApi.pluginSettings.network.requestPacingMs = requestPacingMs;
      touched = true;
    }

    if (pluginApi.pluginSettings.network.maxRetryAttempts === undefined) {
      pluginApi.pluginSettings.network.maxRetryAttempts = maxRetryAttempts;
      touched = true;
    }

    if (pluginApi.pluginSettings.network.retryBaseDelayMs === undefined) {
      pluginApi.pluginSettings.network.retryBaseDelayMs = retryBaseDelayMs;
      touched = true;
    }

    var normalizedLoggingMode = normalizeDiagnosticsMode(
        pluginApi.pluginSettings?.diagnostics?.loggingMode,
        diagnosticsModeSetting,
        "normal");
    if (pluginApi.pluginSettings.diagnostics.loggingMode !== normalizedLoggingMode) {
      pluginApi.pluginSettings.diagnostics.loggingMode = normalizedLoggingMode;
      touched = true;
    }

    if (touched) {
      pluginApi.saveSettings();
    }
  }

  function saveState() {
    saveStateQueued = true;
    saveStateTimer.restart();
  }

  function performSaveState() {
    if (!saveStateQueued || cacheDir === "") {
      return;
    }
    saveStateQueued = false;

    var stateData = {
      searchQuery: searchQuery,
      qualityMode: qualityMode,
      selectedMangaId: selectedManga ? selectedManga.id : "",
      selectedChapterId: currentChapter ? currentChapter.id : "",
      readerAnchor: readerViewportAnchor,
      timestamp: nowSec()
    };

    try {
      ensureCacheDir();
      stateCacheFile.setText(JSON.stringify(stateData, null, 2));
    } catch (e) {
      Logger.e("MangaDex", "Failed to save state: " + e);
    }
  }

  function loadStateFromCache() {
    try {
      var text = stateCacheFile.text();
      if (!text || text.trim() === "") {
        return;
      }

      var cached = JSON.parse(text);
      searchQuery = cached.searchQuery || "";
      qualityMode = cached.qualityMode || defaultQualityMode;
      pendingMangaId = cached.selectedMangaId || "";
      pendingChapterId = cached.selectedChapterId || "";
      readerViewportAnchor = normalizeReaderAnchorData(cached.readerAnchor, pendingChapterId);

      if (pendingMangaId && pendingMangaId !== "") {
        Qt.callLater(function() {
          selectMangaById(pendingMangaId);
        });
      }
    } catch (e) {
      Logger.e("MangaDex", "Failed to parse cached state: " + e);
    }
  }

  function persistRefreshToken() {
    if (!pluginApi || !pluginApi.pluginSettings || !pluginApi.pluginSettings.auth) {
      return;
    }

    if (rememberSession) {
      pluginApi.pluginSettings.auth.refreshToken = refreshToken;
    } else {
      pluginApi.pluginSettings.auth.refreshToken = "";
    }
    pluginApi.saveSettings();
  }

  function restoreSessionFromSettings() {
    if (!pluginApi || !rememberSession) {
      return;
    }

    var storedRefresh = pluginApi?.pluginSettings?.auth?.refreshToken || "";
    if (!storedRefresh || storedRefresh.trim() === "") {
      return;
    }

    refreshToken = storedRefresh;
    refreshAccessToken(function(ok) {
      if (!ok) {
        authError = "Stored session expired. Please log in again.";
      }
    });
  }

  function clearSession(showNotice) {
    accessToken = "";
    refreshToken = "";
    accessTokenExpiresAt = 0;
    authError = "";
    readMarkers = ({});
    mangaReadingStatus = "";

    if (pluginApi?.pluginSettings?.auth) {
      pluginApi.pluginSettings.auth.refreshToken = "";
      pluginApi.saveSettings();
    }

    if (showNotice) {
      ToastService.showNotice("MangaDex session cleared");
    }
  }

  function applyAuthSettings(clientId, clientSecret, identity, rememberSessionValue) {
    if (!pluginApi) {
      return;
    }

    if (!pluginApi.pluginSettings.auth) {
      pluginApi.pluginSettings.auth = {};
    }

    pluginApi.pluginSettings.auth.clientId = (clientId || "").trim();
    pluginApi.pluginSettings.auth.clientSecret = (clientSecret || "").trim();
    pluginApi.pluginSettings.auth.identity = (identity || "").trim();
    // Keep backward compatibility with previous setting key.
    pluginApi.pluginSettings.auth.username = pluginApi.pluginSettings.auth.identity;
    pluginApi.pluginSettings.auth.rememberSession = !!rememberSessionValue;

    if (!rememberSessionValue) {
      pluginApi.pluginSettings.auth.refreshToken = "";
      clearSession(false);
    }

    pluginApi.saveSettings();
  }

  // --------------------
  // Auth
  // --------------------
  function requestLogin(password) {
    if (authBusy) {
      Diagnostics.debug("auth.login.skip.busy", {}, "Skipped login while auth is already in progress");
      return;
    }

    if (!configuredClientId || !configuredClientSecret || !configuredIdentity) {
      authError = "Set client ID, client secret, and username/email in settings first.";
      Diagnostics.warn("auth.login.invalid_config", {
        hasClientId: configuredClientId !== "",
        hasClientSecret: configuredClientSecret !== "",
        hasIdentity: configuredIdentity !== ""
      }, "Login blocked due to missing auth configuration");
      return;
    }

    var normalizedPassword = (password || "").trim();
    if (normalizedPassword === "") {
      if (hasRefreshToken) {
        authError = "No password provided. Trying saved session...";
        Diagnostics.info("auth.login.restore_session", {
          hasRefreshToken: hasRefreshToken
        }, "No password provided, attempting session restore");
        refreshAccessToken(function(ok) {
          if (!ok) {
            authError = "Saved session expired. Enter password for a new login.";
          } else {
            authError = "";
            ToastService.showNotice("MangaDex session restored");
          }
        });
        return;
      }

      authError = "Password is required for first login.";
      Diagnostics.warn("auth.login.password_missing", {}, "Password missing for initial login");
      return;
    }

    authBusy = true;
    authError = "";

    Diagnostics.info("auth.login.start", {
      identity: configuredIdentity,
      hasRefreshToken: hasRefreshToken
    }, "Requesting password token");

    AuthService.requestPasswordToken(
      configuredClientId,
      configuredClientSecret,
      configuredIdentity,
      normalizedPassword,
      function(tokenData) {
        authBusy = false;
        accessToken = tokenData.accessToken;
        refreshToken = tokenData.refreshToken || refreshToken;
        accessTokenExpiresAt = nowSec() + Math.max(30, Number(tokenData.expiresIn || 900) - 20);
        persistRefreshToken();
        ToastService.showNotice("Signed in to MangaDex");

        Diagnostics.info("auth.login.success", {
          identity: configuredIdentity,
          expiresIn: Number(tokenData.expiresIn || 0)
        }, "Password login succeeded");

        if (selectedManga) {
          loadReadMarkersForManga(selectedManga.id);
          loadMangaStatusForManga(selectedManga.id);
        }
      },
      function(errorObj) {
        authBusy = false;
        authError = errorObj.message || "Login failed";
        Diagnostics.error("auth.login.failure", {
          status: Number(errorObj?.status || 0),
          message: errorObj?.message || ""
        }, "Password login failed");
      }
    , {
      timerHost: root,
      maxRetries: maxRetryAttempts,
      backoffBaseMs: retryBaseDelayMs,
      pacingMs: requestPacingMs,
      context: {
        operation: "auth-password-login",
        identity: configuredIdentity
      }
    });
  }

  function refreshAccessToken(done) {
    if (authBusy) {
      if (done) {
        done(false);
      }
      Diagnostics.debug("auth.refresh.skip.busy", {}, "Skipped refresh while auth request is busy");
      return;
    }

    if (!refreshToken || refreshToken.trim() === "") {
      if (done) {
        done(false);
      }
      Diagnostics.debug("auth.refresh.skip.no_token", {}, "Skipped refresh because no refresh token exists");
      return;
    }

    authBusy = true;
    Diagnostics.info("auth.refresh.start", {
      identity: configuredIdentity
    }, "Refreshing access token");

    AuthService.refreshAccessToken(
      configuredClientId,
      configuredClientSecret,
      refreshToken,
      function(tokenData) {
        authBusy = false;
        accessToken = tokenData.accessToken;
        if (tokenData.refreshToken && tokenData.refreshToken !== "") {
          refreshToken = tokenData.refreshToken;
        }
        accessTokenExpiresAt = nowSec() + Math.max(30, Number(tokenData.expiresIn || 900) - 20);
        authError = "";
        persistRefreshToken();
        Diagnostics.info("auth.refresh.success", {
          expiresIn: Number(tokenData.expiresIn || 0)
        }, "Access token refresh succeeded");
        if (done) {
          done(true);
        }
      },
      function(errorObj) {
        authBusy = false;
        authError = errorObj.message || "Session refresh failed";
        Diagnostics.error("auth.refresh.failure", {
          status: Number(errorObj?.status || 0),
          message: errorObj?.message || ""
        }, "Access token refresh failed");
        clearSession(false);
        if (done) {
          done(false);
        }
      }
    , {
      timerHost: root,
      maxRetries: maxRetryAttempts,
      backoffBaseMs: retryBaseDelayMs,
      pacingMs: requestPacingMs,
      context: {
        operation: "auth-refresh",
        identity: configuredIdentity
      }
    });
  }

  function ensureValidAccessToken(done) {
    if (hasAccessToken && nowSec() < accessTokenExpiresAt) {
      done(accessToken);
      return;
    }

    if (hasRefreshToken) {
      refreshAccessToken(function(ok) {
        done(ok ? accessToken : "");
      });
      return;
    }

    done("");
  }

  // --------------------
  // Discovery and feed
  // --------------------
  function searchManga(reset) {
    if (isLoadingSearch) {
      Diagnostics.debug("search.skip.loading", {
        query: searchQuery,
        reset: !!reset
      }, "Skipped search while previous request is still active");
      return;
    }

    if (isCoolingDown()) {
      searchError = "Rate limit cooldown active for " + cooldownRemainingSec() + "s";
      Diagnostics.warn("search.skip.cooldown", {
        query: searchQuery,
        cooldownRemainingSec: cooldownRemainingSec(),
        reset: !!reset
      }, "Search blocked by active cooldown");
      return;
    }

    var query = (searchQuery || "").trim();
    if (query === "") {
      if (reset) {
        searchResults = [];
        searchOffset = 0;
        hasMoreSearch = false;
      }
      Diagnostics.debug("search.skip.empty_query", {
        reset: !!reset
      }, "Search query was empty");
      return;
    }

    var requestOffset = PaginationRules.clampOffset(reset ? 0 : searchOffset);
    var requestLimit = PaginationRules.clampLimit(searchPageSize, 20);

    if (reset) {
      hasMoreSearch = true;
      searchError = "";
      showFollowedFeed = false;
      followedError = "";
    }

    if (!reset && !hasMoreSearch) {
      Diagnostics.debug("search.skip.no_more", {
        query: query,
        offset: requestOffset
      }, "No more search pages available");
      return;
    }

    isLoadingSearch = true;
    Diagnostics.info("search.request.start", {
      query: query,
      offset: requestOffset,
      limit: requestLimit,
      reset: !!reset
    }, "Searching manga");

    try {
      MangaDexApi.searchManga(
        query,
        requestOffset,
        requestLimit,
        {
          translatedLanguages: translatedLanguages,
          contentRatings: contentRatings
        },
        "",
        function(responseObj) {
          isLoadingSearch = false;

          var incoming = responseObj.data || [];
          var existing = reset ? [] : searchResults;
          var mergeResult = SearchMerge.mergeByMangaId(existing, incoming);
          searchResults = mergeResult.merged;

          var nextOffset = PaginationRules.computeNextOffset(requestOffset, mergeResult.incomingCount);
          searchOffset = nextOffset;
          hasMoreSearch = PaginationRules.hasMoreResults(mergeResult.incomingCount, requestLimit, nextOffset);

          if (searchResults.length === 0) {
            searchError = "No manga found for this query.";
          } else {
            searchError = "";
          }

          Diagnostics.info("search.request.success", {
            query: query,
            offset: requestOffset,
            returnedCount: mergeResult.incomingCount,
            dedupedCount: mergeResult.dedupedCount,
            appendedCount: mergeResult.appendedCount,
            totalVisible: searchResults.length,
            hasMore: hasMoreSearch
          }, "Search completed");

          saveState();
        },
        function(errorObj) {
          isLoadingSearch = false;
          applyRateLimitIfNeeded(errorObj);
          searchError = parseApiError(errorObj, "Failed to search manga.");
          Diagnostics.error("search.request.failure", {
            query: query,
            offset: requestOffset,
            status: Number(errorObj?.status || 0),
            message: errorObj?.message || "",
            requestId: errorObj?.requestId || ""
          }, "Search request failed");
        }
      ,
      createApiRequestOptions("search", {
        queryLength: query.length,
        offset: requestOffset,
        limit: requestLimit,
        reset: !!reset
      }));
    } catch (e) {
      isLoadingSearch = false;
      searchError = "Search initialization failed: " + e;
      Diagnostics.error("search.request.exception", {
        query: query,
        offset: requestOffset,
        exception: String(e)
      }, "Search request setup threw an exception");
    }
  }

  function loadMoreSearch() {
    if (!hasMoreSearch) {
      return;
    }
    searchManga(false);
  }

  function selectManga(manga) {
    if (!manga || !manga.id) {
      return;
    }

    Diagnostics.info("manga.select", {
      mangaId: manga.id,
      title: ReaderService.mangaTitle(manga, preferredLanguage)
    }, "Selected manga");

    selectedManga = manga;
    showFollowedFeed = false;
    followedError = "";
    chapters = [];
    currentChapter = null;
    pageUrls = [];
    chapterLoadState = "idle";
    readerError = "";
    chapterError = "";
    readMarkers = ({});
    mangaReadingStatus = "";
    resetPageSlotStates("select_manga");
    bumpReaderRenderEpoch("chapter_changed", false);

    loadMangaFeed(manga.id);
    loadReadMarkersForManga(manga.id);
    loadMangaStatusForManga(manga.id);
    saveState();
  }

  function selectMangaById(mangaId) {
    if (!mangaId || mangaId.trim() === "") {
      return;
    }

    Diagnostics.info("manga.lookup.start", {
      mangaId: mangaId
    }, "Loading manga details by id");

    MangaDexApi.getMangaById(
      mangaId,
      "",
      function(responseObj) {
        if (!responseObj || !responseObj.data) {
          return;
        }

        var manga = responseObj.data;
        var mergedLookup = SearchMerge.mergeByMangaId([manga], searchResults);
        searchResults = mergedLookup.merged;

        Diagnostics.info("manga.lookup.success", {
          mangaId: mangaId,
          title: ReaderService.mangaTitle(manga, preferredLanguage)
        }, "Loaded manga by id");

        selectManga(manga);
      },
      function(errorObj) {
        searchError = parseApiError(errorObj, "Failed to load manga by id.");
        Diagnostics.error("manga.lookup.failure", {
          mangaId: mangaId,
          status: Number(errorObj?.status || 0),
          message: errorObj?.message || "",
          requestId: errorObj?.requestId || ""
        }, "Failed to load manga by id");
      }
    ,
    createApiRequestOptions("manga-by-id", {
      mangaId: mangaId
    }));
  }

  function loadMangaFeed(mangaId) {
    if (!mangaId) {
      return;
    }

    if (isCoolingDown()) {
      chapterError = "Rate limit cooldown active for " + cooldownRemainingSec() + "s";
      Diagnostics.warn("feed.skip.cooldown", {
        mangaId: mangaId,
        cooldownRemainingSec: cooldownRemainingSec()
      }, "Feed request blocked by cooldown");
      return;
    }

    isLoadingChapters = true;
    chapterError = "";
    Diagnostics.info("feed.request.start", {
      mangaId: mangaId,
      translatedLanguages: translatedLanguages,
      contentRatings: contentRatings
    }, "Loading manga chapter feed");

    MangaDexApi.getMangaFeed(
      mangaId,
      0,
      100,
      {
        translatedLanguages: translatedLanguages,
        contentRatings: contentRatings
      },
      "",
      function(responseObj) {
        isLoadingChapters = false;
        chapters = ReaderService.sortChapters(responseObj.data || []);

        var nextCache = {};
        for (var key in mangaFeedCache) {
          if (mangaFeedCache.hasOwnProperty(key)) {
            nextCache[key] = mangaFeedCache[key];
          }
        }
        nextCache[mangaId] = chapters.slice(0);
        mangaFeedCache = nextCache;

        Diagnostics.info("feed.request.success", {
          mangaId: mangaId,
          chapterCount: chapters.length
        }, "Loaded manga chapter feed");

        if (chapters.length === 0) {
          chapterError = "No chapters found for this manga and filter set.";
          return;
        }

        if (pendingChapterId && pendingChapterId !== "") {
          for (var i = 0; i < chapters.length; i++) {
            if (chapters[i].id === pendingChapterId) {
              openChapter(chapters[i]);
              pendingChapterId = "";
              return;
            }
          }
          pendingChapterId = "";
        }
      },
      function(errorObj) {
        isLoadingChapters = false;
        applyRateLimitIfNeeded(errorObj);
        chapterError = parseApiError(errorObj, "Failed to load chapter feed.");

        var cachedFeed = mangaFeedCache[mangaId];
        if (Object.prototype.toString.call(cachedFeed) === "[object Array]" && cachedFeed.length > 0) {
          chapters = cachedFeed.slice(0);
        }

        Diagnostics.error("feed.request.failure", {
          mangaId: mangaId,
          status: Number(errorObj?.status || 0),
          message: errorObj?.message || "",
          requestId: errorObj?.requestId || "",
          restoredFromCache: !!(cachedFeed && cachedFeed.length > 0)
        }, "Failed to load manga chapter feed");
      }
    ,
    createApiRequestOptions("manga-feed", {
      mangaId: mangaId,
      limit: 100,
      offset: 0
    }));
  }

  function loadFollowedFeed() {
    ensureValidAccessToken(function(token) {
      if (!token || token === "") {
        followedError = "Sign in to load followed feed.";
        return;
      }

      if (isCoolingDown()) {
        followedError = "Rate limit cooldown active for " + cooldownRemainingSec() + "s";
        Diagnostics.warn("feed.followed.skip.cooldown", {
          cooldownRemainingSec: cooldownRemainingSec()
        }, "Followed feed blocked by cooldown");
        return;
      }

      isLoadingChapters = true;
      followedError = "";
      chapterError = "";
      selectedManga = null;
      showFollowedFeed = true;
      currentChapter = null;
      pageUrls = [];
      chapterLoadState = "idle";
      resetPageSlotStates("followed_feed_open");
      bumpReaderRenderEpoch("chapter_changed", false);

      Diagnostics.info("feed.followed.request.start", {
        translatedLanguages: translatedLanguages,
        contentRatings: contentRatings
      }, "Loading followed feed");

      MangaDexApi.getFollowedFeed(
        0,
        100,
        {
          translatedLanguages: translatedLanguages,
          contentRatings: contentRatings
        },
        token,
        function(responseObj) {
          isLoadingChapters = false;
          chapters = ReaderService.sortChapters(responseObj.data || []);
          Diagnostics.info("feed.followed.request.success", {
            chapterCount: chapters.length
          }, "Loaded followed feed");
          if (chapters.length === 0) {
            followedError = "No followed-feed chapters available for current filters.";
          }
        },
        function(errorObj) {
          isLoadingChapters = false;
          applyRateLimitIfNeeded(errorObj);
          followedError = parseApiError(errorObj, "Failed to load followed feed.");
          Diagnostics.error("feed.followed.request.failure", {
            status: Number(errorObj?.status || 0),
            message: errorObj?.message || "",
            requestId: errorObj?.requestId || ""
          }, "Failed to load followed feed");
        }
      ,
      createApiRequestOptions("followed-feed", {
        limit: 100,
        offset: 0
      }));
    });
  }

  // --------------------
  // Reader
  // --------------------
  function openChapter(chapter) {
    if (!chapter || !chapter.id) {
      return;
    }

    Diagnostics.info("chapter.open", {
      chapterId: chapter.id,
      label: ReaderService.chapterLabel(chapter)
    }, "Opening chapter");

    currentChapter = chapter;
    atHomeMetadata = null;
    pageUrls = [];
    readerError = "";
    chapterRetryUsed = false;
    chapterQualityFallbackUsed = false;
    chapterTargetedRetryUsed = false;
    chapterRecoveryInProgress = false;
    chapterLoadState = "loading";
    resetPageSlotStates("open_chapter");
    bumpReaderRenderEpoch("chapter_changed", false);

    loadChapterPages(chapter.id);
    saveState();
  }

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
    var qualityPart = String(qualityModeValue || defaultQualityMode || "data-saver").trim();
    var pagePart = String(pageIdentityValue || "").trim();
    if (pagePart === "") {
      pagePart = "page-" + String(Math.max(0, Number(fallbackIndex || 0)));
    }

    return chapterPart + "::" + qualityPart + "::" + pagePart;
  }

  function pageCacheKeyForEntry(pageEntry, fallbackIndex) {
    var normalizedEntry = normalizePageEntry(pageEntry);
    if (!normalizedEntry) {
      return "";
    }

    if (normalizedEntry.cacheKey && normalizedEntry.cacheKey !== "") {
      return normalizedEntry.cacheKey;
    }

    return buildPageCacheKeyForValues(
      normalizedEntry.chapterId || currentChapter?.id || "",
      normalizedEntry.qualityMode || qualityMode,
      normalizedEntry.pageIdentity,
      normalizedEntry.pageIndex >= 0 ? normalizedEntry.pageIndex : fallbackIndex);
  }

  function commitPageImageCacheState(entriesValue, lruValue, reason) {
    pageImageCacheEntries = entriesValue;
    pageImageCacheLru = lruValue;
    pageImageCacheRevision = pageImageCacheRevision + 1;

    Diagnostics.debug("reader.cache.state_commit", {
      reason: reason || "update",
      cacheEntries: Object.keys(entriesValue || {}).length,
      lruSize: (lruValue || []).length,
      revision: pageImageCacheRevision
    }, "Committed page image cache state update");
  }

  function prunePageImageCache() {
    var entries = cloneObject(pageImageCacheEntries);
    var lru = cloneArray(pageImageCacheLru);
    var evicted = [];

    if (lru.length > 0 && pageCachePerChapterMaxEntries > 0) {
      var chapterSeen = {};
      for (var i = lru.length - 1; i >= 0; i--) {
        var key = lru[i];
        var entry = entries[key];
        if (!entry || entry.valid !== true) {
          continue;
        }

        var chapterKey = String(entry.chapterId || "");
        chapterSeen[chapterKey] = Number(chapterSeen[chapterKey] || 0) + 1;
        if (chapterSeen[chapterKey] > pageCachePerChapterMaxEntries) {
          evicted.push(key);
          lru.splice(i, 1);
        }
      }
    }

    while (lru.length > pageCacheMaxEntries) {
      evicted.push(lru.shift());
    }

    if (evicted.length === 0) {
      return;
    }

    for (var j = 0; j < evicted.length; j++) {
      var evictKey = evicted[j];
      var evictEntry = entries[evictKey];
      if (!evictEntry) {
        continue;
      }
      evictEntry.valid = false;
      evictEntry.evicted = true;
      evictEntry.evictedAtMs = Date.now();
      entries[evictKey] = evictEntry;
    }

    commitPageImageCacheState(entries, lru, "prune");
  }

  function touchPageCacheKey(cacheKey) {
    var keyValue = String(cacheKey || "").trim();
    if (keyValue === "") {
      return;
    }

    var entries = cloneObject(pageImageCacheEntries);
    var entry = entries[keyValue];
    if (!entry || entry.valid !== true) {
      return;
    }

    entry.lastAccessMs = Date.now();
    entries[keyValue] = entry;

    var lru = cloneArray(pageImageCacheLru);
    var existingIndex = lru.indexOf(keyValue);
    if (existingIndex >= 0) {
      lru.splice(existingIndex, 1);
    }
    lru.push(keyValue);

    commitPageImageCacheState(entries, lru, "touch");
    prunePageImageCache();
  }

  function touchPageCacheEntry(pageEntry, fallbackIndex) {
    touchPageCacheKey(pageCacheKeyForEntry(pageEntry, fallbackIndex));
  }

  function isPageCached(pageEntry, fallbackIndex) {
    var cacheKey = pageCacheKeyForEntry(pageEntry, fallbackIndex);
    if (cacheKey === "") {
      return false;
    }

    var entry = pageImageCacheEntries[cacheKey];
    if (!entry || entry.valid !== true) {
      return false;
    }

    if (String(entry.source || "").trim() === "") {
      return false;
    }

    return Number(entry.width || 0) > 0 && Number(entry.height || 0) > 0;
  }

  function registerPageImageReady(pageEntry, imageWidth, imageHeight, fallbackIndex) {
    var normalizedEntry = normalizePageEntry(pageEntry);
    if (!normalizedEntry) {
      return;
    }

    var cacheKey = pageCacheKeyForEntry(normalizedEntry, fallbackIndex);
    if (cacheKey === "") {
      return;
    }

    var widthValue = Number(imageWidth || 0);
    var heightValue = Number(imageHeight || 0);
    var dimensionsValid = widthValue > 0 && heightValue > 0;
    var chapterIdValue = String(normalizedEntry.chapterId || currentChapter?.id || "");

    var entries = cloneObject(pageImageCacheEntries);
    var previous = entries[cacheKey] && typeof entries[cacheKey] === "object"
        ? cloneObject(entries[cacheKey])
        : {};

    previous.cacheKey = cacheKey;
    previous.chapterId = chapterIdValue;
    previous.qualityMode = String(normalizedEntry.qualityMode || qualityMode || defaultQualityMode);
    previous.pageIdentity = String(normalizedEntry.pageIdentity || "");
    previous.pageIndex = normalizedEntry.pageIndex >= 0 ? normalizedEntry.pageIndex : Math.max(0, Number(fallbackIndex || 0));
    previous.source = normalizedEntry.source;
    previous.canonicalSource = normalizedEntry.canonicalSource;
    previous.width = dimensionsValid ? widthValue : Number(previous.width || 0);
    previous.height = dimensionsValid ? heightValue : Number(previous.height || 0);
    previous.estimatedSizeBytes = dimensionsValid ? Math.round(widthValue * heightValue * 4) : Number(previous.estimatedSizeBytes || 0);
    previous.valid = dimensionsValid;
    previous.evicted = false;
    previous.updatedAtMs = Date.now();
    previous.lastAccessMs = previous.updatedAtMs;
    if (dimensionsValid) {
      previous.corruptReason = "";
      previous.failureCount = 0;
      previous.failedUrl = "";
    } else {
      previous.corruptReason = "invalid-dimensions";
      previous.failureCount = Number(previous.failureCount || 0) + 1;
    }

    entries[cacheKey] = previous;

    var lru = cloneArray(pageImageCacheLru);
    var existingIndex = lru.indexOf(cacheKey);
    if (existingIndex >= 0) {
      lru.splice(existingIndex, 1);
    }
    if (previous.valid === true) {
      lru.push(cacheKey);
    }

    commitPageImageCacheState(entries, lru, "register-ready");
    prunePageImageCache();

    Diagnostics.debug("reader.cache.page_ready", {
      chapterId: chapterIdValue,
      pageIdentity: previous.pageIdentity,
      cacheKey: cacheKey,
      width: Math.round(widthValue),
      height: Math.round(heightValue),
      valid: previous.valid
    }, "Recorded page image readiness in cache index");

    if (previous.valid === true) {
      markPageSlotReady(normalizedEntry, previous.pageIndex, normalizedEntry.source);
    } else {
      markPageSlotError(normalizedEntry, previous.pageIndex, "invalid-dimensions", normalizedEntry.source);
    }
  }

  function invalidatePageCacheEntry(pageEntry, failedUrl, reason, fallbackIndex) {
    var normalizedEntry = normalizePageEntry(pageEntry);
    if (!normalizedEntry) {
      return;
    }

    var cacheKey = pageCacheKeyForEntry(normalizedEntry, fallbackIndex);
    if (cacheKey === "") {
      return;
    }

    var entries = cloneObject(pageImageCacheEntries);
    var existing = entries[cacheKey] && typeof entries[cacheKey] === "object"
        ? cloneObject(entries[cacheKey])
        : {};

    existing.cacheKey = cacheKey;
    existing.chapterId = String(existing.chapterId || normalizedEntry.chapterId || currentChapter?.id || "");
    existing.qualityMode = String(existing.qualityMode || normalizedEntry.qualityMode || qualityMode || defaultQualityMode);
    existing.pageIdentity = String(existing.pageIdentity || normalizedEntry.pageIdentity || "");
    existing.pageIndex = normalizedEntry.pageIndex >= 0
        ? normalizedEntry.pageIndex
        : Math.max(0, Number(fallbackIndex || existing.pageIndex || 0));
    existing.valid = false;
    existing.evicted = false;
    existing.corruptReason = String(reason || "invalid");
    existing.failedUrl = String(failedUrl || "");
    existing.updatedAtMs = Date.now();
    existing.failureCount = Number(existing.failureCount || 0) + 1;

    entries[cacheKey] = existing;

    var lru = cloneArray(pageImageCacheLru);
    var existingIndex = lru.indexOf(cacheKey);
    if (existingIndex >= 0) {
      lru.splice(existingIndex, 1);
    }

    commitPageImageCacheState(entries, lru, "invalidate");
    Diagnostics.warn("reader.cache.page_invalidated", {
      chapterId: existing.chapterId,
      pageIdentity: existing.pageIdentity,
      cacheKey: cacheKey,
      reason: existing.corruptReason,
      failureCount: existing.failureCount
    }, "Invalidated page cache entry due to render or delivery failure");

    markPageSlotError(normalizedEntry, existing.pageIndex, existing.corruptReason, existing.failedUrl || normalizedEntry.source);
  }

  function buildRuntimePageEntries(atHomeResponse, modeValue) {
    var resolvedUrls = ReaderService.buildPageUrls(atHomeResponse, modeValue);
    var entries = [];
    var chapterIdValue = currentChapter?.id || "";
    var qualityModeValue = String(modeValue || qualityMode || defaultQualityMode);

    for (var i = 0; i < resolvedUrls.length; i++) {
      var normalizedEntry = normalizePageEntry(resolvedUrls[i]);
      if (normalizedEntry) {
        normalizedEntry.pageIndex = i;
        normalizedEntry.chapterId = chapterIdValue;
        normalizedEntry.qualityMode = qualityModeValue;
        normalizedEntry.cacheKey = buildPageCacheKeyForValues(
          chapterIdValue,
          qualityModeValue,
          normalizedEntry.pageIdentity,
          i);
        entries.push(normalizedEntry);
      }
    }

    Diagnostics.debug("chapter.pages.built", {
      chapterId: currentChapter?.id || "",
      qualityMode: modeValue,
      pageCount: entries.length
    }, "Built runtime page entries");

    return entries;
  }

  function pageEntryMatchesUrl(pageEntry, failedUrl) {
    var normalizedEntry = normalizePageEntry(pageEntry);
    if (!normalizedEntry) {
      return false;
    }

    if (normalizedEntry.source === failedUrl || normalizedEntry.canonicalSource === failedUrl) {
      return true;
    }

    var sourceFallback = toUploadsFallbackUrl(normalizedEntry.source);
    var canonicalFallback = toUploadsFallbackUrl(normalizedEntry.canonicalSource);

    if ((sourceFallback !== "" && sourceFallback === failedUrl)
        || (canonicalFallback !== "" && canonicalFallback === failedUrl)) {
      return true;
    }

    return false;
  }

  function loadChapterPages(chapterId) {
    if (!chapterId) {
      return;
    }

    var loadToken = chapterLoadToken + 1;
    chapterLoadToken = loadToken;

    if (isCoolingDown()) {
      readerError = "Rate limit cooldown active for " + cooldownRemainingSec() + "s";
      chapterLoadState = "error";
      Diagnostics.warn("chapter.load.skip.cooldown", {
        chapterId: chapterId,
        loadToken: loadToken,
        cooldownRemainingSec: cooldownRemainingSec()
      }, "Chapter load blocked by cooldown");
      return;
    }

    isLoadingPages = true;
    chapterRecoveryInProgress = true;
    chapterLoadState = "loading";
    atHomeMetadata = null;
    pageUrls = [];
    readerError = "";
    resetPageSlotStates("chapter_loading");

    Diagnostics.info("chapter.load.start", {
      chapterId: chapterId,
      loadToken: loadToken,
      qualityMode: qualityMode
    }, "Resolving At-Home server for chapter");

    MangaDexApi.getAtHomeServer(
      chapterId,
      true,
      function(responseObj) {
        if (loadToken !== chapterLoadToken) {
          Diagnostics.warn("chapter.load.stale_success", {
            chapterId: chapterId,
            loadToken: loadToken,
            activeLoadToken: chapterLoadToken
          }, "Ignored stale chapter load success callback");
          return;
        }

        isLoadingPages = false;
        chapterRecoveryInProgress = false;
        chapterTargetedRetryUsed = false;

        if (!currentChapter || currentChapter.id !== chapterId) {
          Diagnostics.warn("chapter.load.stale_chapter", {
            chapterId: chapterId,
            activeChapterId: currentChapter?.id || "",
            loadToken: loadToken
          }, "Ignored chapter load callback for inactive chapter");
          return;
        }

        atHomeMetadata = responseObj;
        pageUrls = buildRuntimePageEntries(responseObj, qualityMode);
        hydratePageSlotStates("chapter_load_success");
        bumpReaderRenderEpoch("page_model_changed", false);

        if (pageUrls.length === 0) {
          chapterLoadState = "error";
          readerError = "Chapter has no readable pages for selected quality.";
          Diagnostics.warn("chapter.load.empty", {
            chapterId: chapterId,
            loadToken: loadToken,
            qualityMode: qualityMode
          }, "Chapter resolved but no readable pages were produced");
          return;
        }

        chapterLoadState = "success";
        chapterRetryUsed = false;
        chapterQualityFallbackUsed = false;
        Diagnostics.info("chapter.load.success", {
          chapterId: chapterId,
          loadToken: loadToken,
          pageCount: pageUrls.length,
          qualityMode: qualityMode
        }, "Chapter pages resolved successfully");
      },
      function(errorObj) {
        if (loadToken !== chapterLoadToken) {
          Diagnostics.warn("chapter.load.stale_failure", {
            chapterId: chapterId,
            loadToken: loadToken,
            activeLoadToken: chapterLoadToken,
            status: Number(errorObj?.status || 0)
          }, "Ignored stale chapter load failure callback");
          return;
        }

        isLoadingPages = false;
        chapterRecoveryInProgress = false;
        chapterLoadState = "error";
        applyRateLimitIfNeeded(errorObj);
        readerError = parseApiError(errorObj, "Failed to resolve chapter pages.");
        resetPageSlotStates("chapter_load_failure");
        Diagnostics.error("chapter.load.failure", {
          chapterId: chapterId,
          loadToken: loadToken,
          status: Number(errorObj?.status || 0),
          message: errorObj?.message || "",
          requestId: errorObj?.requestId || ""
        }, "Chapter page resolution failed");
      }
    ,
    createApiRequestOptions("chapter-at-home", {
      chapterId: chapterId,
      loadToken: loadToken,
      qualityMode: qualityMode
    }));
  }

  function toUploadsFallbackUrl(url) {
    var source = String(url || "").trim();
    if (source === "") {
      return "";
    }

    var lower = source.toLowerCase();
    if (lower.indexOf("https://uploads.mangadex.org/") === 0 || lower.indexOf("http://uploads.mangadex.org/") === 0) {
      return "";
    }

    var match = source.match(/^https?:\/\/[^\/]+(\/.*)$/);
    if (!match || !match[1]) {
      return "";
    }

    var path = String(match[1]);
    if (path.indexOf("/data/") !== 0 && path.indexOf("/data-saver/") !== 0) {
      return "";
    }

    return "https://uploads.mangadex.org" + path;
  }

  function shouldHandleChapterImageFailure(failedUrl) {
    if (Object.prototype.toString.call(pageUrls) !== "[object Array]") {
      return true;
    }

    var normalizedFailedUrl = String(failedUrl || "").trim();
    if (normalizedFailedUrl === "") {
      return true;
    }

    for (var i = 0; i < pageUrls.length; i++) {
      if (pageEntryMatchesUrl(pageUrls[i], normalizedFailedUrl)) {
        return true;
      }
    }

    return false;
  }

  function findPageIndexForFailedUrl(failedUrl) {
    if (Object.prototype.toString.call(pageUrls) !== "[object Array]") {
      return -1;
    }

    var normalizedFailedUrl = String(failedUrl || "").trim();
    if (normalizedFailedUrl === "") {
      return -1;
    }

    for (var i = 0; i < pageUrls.length; i++) {
      if (pageEntryMatchesUrl(pageUrls[i], normalizedFailedUrl)) {
        return i;
      }
    }

    return -1;
  }

  function findReplacementPageIndexByIdentity(entries, pageIdentity, fallbackIndex) {
    if (Object.prototype.toString.call(entries) !== "[object Array]") {
      return -1;
    }

    var targetIdentity = String(pageIdentity || "").trim();
    if (targetIdentity !== "") {
      for (var i = 0; i < entries.length; i++) {
        var normalized = normalizePageEntry(entries[i]);
        if (normalized && normalized.pageIdentity === targetIdentity) {
          return i;
        }
      }
    }

    var numericFallback = Math.round(Number(fallbackIndex || 0));
    if (numericFallback >= 0 && numericFallback < entries.length) {
      return numericFallback;
    }

    return -1;
  }

  function replacePageEntryAtIndex(targetIndex, replacementEntry, reason) {
    var indexValue = Math.round(Number(targetIndex || -1));
    if (indexValue < 0 || indexValue >= pageUrls.length) {
      return false;
    }

    var replacement = normalizePageEntry(replacementEntry);
    if (!replacement) {
      return false;
    }

    var updatedPages = cloneArray(pageUrls);
    updatedPages[indexValue] = replacement;
    pageUrls = updatedPages;

    Diagnostics.debug("chapter.page.replace", {
      chapterId: currentChapter?.id || "",
      pageIndex: indexValue,
      pageIdentity: replacement.pageIdentity,
      reason: String(reason || "replace")
    }, "Replaced one page entry atomically without rebuilding full chapter list");

    return true;
  }

  function attemptTargetedPageRecovery(failedUrl, preferredIndex, triggerReason) {
    if (!currentChapter || !currentChapter.id) {
      return false;
    }

    var fallbackIndex = Math.round(Number(preferredIndex));
    var failedIndex = (isNaN(fallbackIndex) || fallbackIndex < 0) ? -1 : fallbackIndex;
    if (failedIndex < 0) {
      failedIndex = findPageIndexForFailedUrl(failedUrl);
    }
    if (failedIndex < 0) {
      return false;
    }

    var failedEntry = normalizePageEntry(pageUrls[failedIndex]);
    if (!failedEntry) {
      return false;
    }

    var recoveryToken = chapterLoadToken + 1;
    chapterLoadToken = recoveryToken;
    chapterRecoveryInProgress = true;
    chapterLoadState = "loading";
    markPageSlotStale(failedEntry, failedIndex, "targeted-recovery-start", failedUrl);

    Diagnostics.warn("chapter.image_failure.targeted_recovery.start", {
      chapterId: currentChapter.id,
      failedUrl: String(failedUrl || ""),
      failedIndex: failedIndex,
      pageIdentity: failedEntry.pageIdentity,
      qualityMode: qualityMode,
      reason: String(triggerReason || "auto"),
      loadToken: recoveryToken
    }, "Attempting targeted page recovery without full chapter reset");

    MangaDexApi.getAtHomeServer(
      currentChapter.id,
      true,
      function(responseObj) {
        if (recoveryToken !== chapterLoadToken) {
          Diagnostics.warn("chapter.image_failure.targeted_recovery.stale", {
            chapterId: currentChapter?.id || "",
            loadToken: recoveryToken,
            activeLoadToken: chapterLoadToken
          }, "Ignoring stale targeted recovery callback");
          return;
        }

        chapterRecoveryInProgress = false;

        if (!currentChapter || !currentChapter.id) {
          return;
        }

        var refreshedEntries = buildRuntimePageEntries(responseObj, qualityMode);
        var replacementIndex = findReplacementPageIndexByIdentity(
          refreshedEntries,
          failedEntry.pageIdentity,
          failedIndex);

        if (replacementIndex < 0) {
          Diagnostics.warn("chapter.image_failure.targeted_recovery.no_match", {
            chapterId: currentChapter.id,
            failedIndex: failedIndex,
            pageIdentity: failedEntry.pageIdentity
          }, "Targeted recovery could not map replacement page; falling back to chapter reload");
          loadChapterPages(currentChapter.id);
          return;
        }

        var replacement = normalizePageEntry(refreshedEntries[replacementIndex]);
        if (!replacement) {
          Diagnostics.warn("chapter.image_failure.targeted_recovery.invalid_replacement", {
            chapterId: currentChapter.id,
            failedIndex: failedIndex,
            replacementIndex: replacementIndex
          }, "Targeted recovery produced invalid replacement entry; falling back to chapter reload");
          loadChapterPages(currentChapter.id);
          return;
        }

        replacement.pageIndex = failedIndex;
        replacement.chapterId = currentChapter.id;
        replacement.qualityMode = qualityMode;
        replacement.pageIdentity = failedEntry.pageIdentity || replacement.pageIdentity;
        replacement.cacheKey = failedEntry.cacheKey || buildPageCacheKeyForValues(
          currentChapter.id,
          qualityMode,
          replacement.pageIdentity,
          failedIndex);

        replacePageEntryAtIndex(failedIndex, replacement, triggerReason || "targeted_recovery");
        atHomeMetadata = responseObj;
        chapterTargetedRetryUsed = false;
        chapterLoadState = "success";
        readerError = "";
        markPageSlotLoading(replacement, failedIndex, "targeted-recovery-success");
        hydratePageSlotStates("targeted_recovery_success");
        bumpReaderRenderEpoch("page_model_changed", false);

        Diagnostics.info("chapter.image_failure.targeted_recovery.success", {
          chapterId: currentChapter.id,
          failedIndex: failedIndex,
          pageIdentity: replacement.pageIdentity,
          qualityMode: qualityMode
        }, "Targeted page recovery updated only the failed page entry");
      },
      function(errorObj) {
        if (recoveryToken !== chapterLoadToken) {
          return;
        }

        chapterRecoveryInProgress = false;
        applyRateLimitIfNeeded(errorObj);
        markPageSlotError(failedEntry, failedIndex, "targeted-recovery-failed", failedUrl);
        Diagnostics.error("chapter.image_failure.targeted_recovery.failure", {
          chapterId: currentChapter?.id || "",
          status: Number(errorObj?.status || 0),
          message: errorObj?.message || "",
          requestId: errorObj?.requestId || ""
        }, "Targeted page recovery failed; falling back to chapter reload");
        loadChapterPages(currentChapter.id);
      }
    ,
    createApiRequestOptions("chapter-at-home-targeted", {
      chapterId: currentChapter.id,
      failedIndex: failedIndex,
      failedUrl: String(failedUrl || ""),
      qualityMode: qualityMode
    }));

    return true;
  }

  function requestPageRefetch(pageEntry, fallbackIndex, reason) {
    if (!currentChapter || !currentChapter.id) {
      return false;
    }

    var resolvedIndex = Math.round(Number(fallbackIndex));
    if (isNaN(resolvedIndex) || resolvedIndex < 0 || resolvedIndex >= pageUrls.length) {
      var normalized = normalizePageEntry(pageEntry);
      if (normalized) {
        resolvedIndex = findReplacementPageIndexByIdentity(pageUrls, normalized.pageIdentity, 0);
      }
    }

    if (resolvedIndex < 0 || resolvedIndex >= pageUrls.length) {
      return false;
    }

    var targetEntry = normalizePageEntry(pageUrls[resolvedIndex]);
    if (!targetEntry) {
      return false;
    }

    if (chapterRecoveryInProgress) {
      return false;
    }

    markPageSlotLoading(targetEntry, resolvedIndex, "manual-refetch");
    chapterTargetedRetryUsed = true;
    var recoveryStarted = attemptTargetedPageRecovery(
      targetEntry.source || String(pageEntry?.source || ""),
      resolvedIndex,
      reason || "manual_refetch");

    if (!recoveryStarted) {
      chapterTargetedRetryUsed = false;
      markPageSlotError(targetEntry, resolvedIndex, "manual-refetch-start-failed", targetEntry.source);
      return false;
    }

    bumpReaderRenderEpoch("manual_refetch", false);
    return true;
  }

  function reloadCurrentChapter() {
    if (!currentChapter) {
      return;
    }
    chapterRetryUsed = false;
    chapterQualityFallbackUsed = false;
    chapterTargetedRetryUsed = false;
    chapterLoadState = "loading";
    Diagnostics.info("chapter.reload", {
      chapterId: currentChapter.id,
      qualityMode: qualityMode
    }, "Manually reloading current chapter");
    loadChapterPages(currentChapter.id);
  }

  function handleChapterImageFailure(failedUrl) {
    if (!currentChapter || chapterRecoveryInProgress) {
      Diagnostics.debug("chapter.image_failure.ignored", {
        chapterId: currentChapter?.id || "",
        chapterRecoveryInProgress: chapterRecoveryInProgress,
        failedUrl: String(failedUrl || "")
      }, "Ignored image failure while recovery is already in progress");
      return;
    }

    var normalizedFailedUrl = String(failedUrl || "").trim();
    var failedIndex = findPageIndexForFailedUrl(normalizedFailedUrl);
    if (failedIndex >= 0 && failedIndex < pageUrls.length) {
      markPageSlotError(pageUrls[failedIndex], failedIndex, "image-failure", normalizedFailedUrl);
    }

    if (!shouldHandleChapterImageFailure(normalizedFailedUrl)) {
      Diagnostics.debug("chapter.image_failure.out_of_scope", {
        chapterId: currentChapter.id,
        failedUrl: normalizedFailedUrl
      }, "Ignored image failure that does not match active page set");
      return;
    }

    if (!chapterTargetedRetryUsed) {
      chapterTargetedRetryUsed = true;
      if (attemptTargetedPageRecovery(normalizedFailedUrl, failedIndex, "auto_recovery")) {
        return;
      }
      chapterTargetedRetryUsed = false;
    }

    if (!chapterRetryUsed) {
      chapterRetryUsed = true;
      chapterLoadState = "loading";
      Diagnostics.warn("chapter.image_failure.retry", {
        chapterId: currentChapter.id,
        failedUrl: normalizedFailedUrl || "",
        qualityMode: qualityMode
      }, "Image load failed, retrying with refreshed At-Home metadata");
      loadChapterPages(currentChapter.id);
      return;
    }

    if (!chapterQualityFallbackUsed) {
      chapterQualityFallbackUsed = true;
      chapterRetryUsed = false;
      qualityMode = qualityMode === "data" ? "data-saver" : "data";
      chapterLoadState = "loading";
      Diagnostics.warn("chapter.image_failure.quality_fallback", {
        chapterId: currentChapter.id,
        failedUrl: normalizedFailedUrl || "",
        qualityMode: qualityMode
      }, "Image load still failing, switching quality mode and retrying");
      readerError = "Switched quality to " + qualityMode + " after image delivery failures.";
      loadChapterPages(currentChapter.id);
      return;
    }

    chapterRecoveryInProgress = false;
    chapterLoadState = "error";
    readerError = "Image delivery failed for this chapter. Try another chapter or retry.";
    Diagnostics.error("chapter.image_failure.terminal", {
      chapterId: currentChapter.id,
      failedUrl: normalizedFailedUrl || "",
      qualityMode: qualityMode
    }, "Chapter image recovery exhausted all retries");
  }

  function openPreviousChapter() {
    if (!currentChapter || !chapters || chapters.length === 0) {
      return;
    }

    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].id === currentChapter.id) {
        if (i > 0) {
          openChapter(chapters[i - 1]);
        }
        return;
      }
    }
  }

  function openNextChapter() {
    if (!currentChapter || !chapters || chapters.length === 0) {
      return;
    }

    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].id === currentChapter.id) {
        if (i < chapters.length - 1) {
          openChapter(chapters[i + 1]);
        }
        return;
      }
    }
  }

  // --------------------
  // Sync
  // --------------------
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

  function chapterIsRead(chapterId) {
    return ReaderService.isChapterRead(readMarkers, chapterId);
  }

  function markChapterRead(chapterId) {
    if (!chapterId || chapterId === "") {
      return;
    }

    var targetMangaId = selectedManga ? selectedManga.id : mangaIdForChapter(currentChapter);
    if (!targetMangaId || targetMangaId === "") {
      readerError = "Cannot mark as read: manga id unavailable.";
      return;
    }

    ensureValidAccessToken(function(token) {
      if (!token || token === "") {
        readerError = "Sign in to sync read markers.";
        Diagnostics.warn("sync.read_marker.auth_required", {
          chapterId: chapterId,
          mangaId: targetMangaId
        }, "Read marker sync skipped due to missing auth");
        return;
      }

      Diagnostics.info("sync.read_marker.request.start", {
        chapterId: chapterId,
        mangaId: targetMangaId
      }, "Syncing read marker");

      MangaDexApi.updateReadMarkers(
        targetMangaId,
        [chapterId],
        [],
        token,
        function() {
          var updated = {};
          for (var key in readMarkers) {
            if (readMarkers.hasOwnProperty(key)) {
              updated[key] = readMarkers[key];
            }
          }
          updated[chapterId] = true;
          readMarkers = updated;
          ToastService.showNotice("Chapter marked as read");
          Diagnostics.info("sync.read_marker.request.success", {
            chapterId: chapterId,
            mangaId: targetMangaId
          }, "Read marker synced");
        },
        function(errorObj) {
          applyRateLimitIfNeeded(errorObj);
          readerError = parseApiError(errorObj, "Failed to sync read marker.");
          Diagnostics.error("sync.read_marker.request.failure", {
            chapterId: chapterId,
            mangaId: targetMangaId,
            status: Number(errorObj?.status || 0),
            message: errorObj?.message || "",
            requestId: errorObj?.requestId || ""
          }, "Failed to sync read marker");
        }
      ,
      createApiRequestOptions("read-marker-update", {
        chapterId: chapterId,
        mangaId: targetMangaId
      }));
    });
  }

  function markCurrentChapterRead() {
    if (!currentChapter) {
      return;
    }
    markChapterRead(currentChapter.id);
  }

  function loadReadMarkersForManga(mangaId) {
    if (!mangaId || mangaId === "") {
      return;
    }

    ensureValidAccessToken(function(token) {
      if (!token || token === "") {
        return;
      }

      Diagnostics.debug("sync.read_markers.request.start", {
        mangaId: mangaId
      }, "Loading read markers");

      MangaDexApi.getMangaReadMarkers(
        mangaId,
        token,
        function(responseObj) {
          var map = {};
          var ids = responseObj.data || [];
          for (var i = 0; i < ids.length; i++) {
            map[ids[i]] = true;
          }
          readMarkers = map;
          Diagnostics.debug("sync.read_markers.request.success", {
            mangaId: mangaId,
            markerCount: ids.length
          }, "Loaded read markers");
        },
        function(errorObj) {
          applyRateLimitIfNeeded(errorObj);
          Diagnostics.warn("sync.read_markers.request.failure", {
            mangaId: mangaId,
            status: Number(errorObj?.status || 0),
            message: errorObj?.message || "",
            requestId: errorObj?.requestId || ""
          }, "Failed to load read markers");
        }
      ,
      createApiRequestOptions("read-markers-get", {
        mangaId: mangaId
      }));
    });
  }

  function loadMangaStatusForManga(mangaId) {
    if (!mangaId || mangaId === "") {
      return;
    }

    ensureValidAccessToken(function(token) {
      if (!token || token === "") {
        mangaReadingStatus = "";
        return;
      }

      Diagnostics.debug("sync.status.request.start", {
        mangaId: mangaId
      }, "Loading manga reading status");

      MangaDexApi.getMangaStatus(
        mangaId,
        token,
        function(responseObj) {
          mangaReadingStatus = responseObj.status || "";
          Diagnostics.debug("sync.status.request.success", {
            mangaId: mangaId,
            status: mangaReadingStatus
          }, "Loaded manga reading status");
        },
        function(errorObj) {
          applyRateLimitIfNeeded(errorObj);
          Diagnostics.warn("sync.status.request.failure", {
            mangaId: mangaId,
            status: Number(errorObj?.status || 0),
            message: errorObj?.message || "",
            requestId: errorObj?.requestId || ""
          }, "Failed to load manga reading status");
        }
      ,
      createApiRequestOptions("status-get", {
        mangaId: mangaId
      }));
    });
  }

  function setMangaReadingStatus(status) {
    var targetMangaId = selectedManga ? selectedManga.id : mangaIdForChapter(currentChapter);
    if (!targetMangaId || targetMangaId === "") {
      return;
    }

    ensureValidAccessToken(function(token) {
      if (!token || token === "") {
        readerError = "Sign in to sync reading status.";
        Diagnostics.warn("sync.status.update.auth_required", {
          mangaId: targetMangaId,
          status: status
        }, "Reading status update skipped due to missing auth");
        return;
      }

      Diagnostics.info("sync.status.update.start", {
        mangaId: targetMangaId,
        status: status
      }, "Updating manga reading status");

      MangaDexApi.setMangaStatus(
        targetMangaId,
        status,
        token,
        function() {
          mangaReadingStatus = status;
          ToastService.showNotice("Reading status updated");
          Diagnostics.info("sync.status.update.success", {
            mangaId: targetMangaId,
            status: status
          }, "Updated manga reading status");
        },
        function(errorObj) {
          applyRateLimitIfNeeded(errorObj);
          readerError = parseApiError(errorObj, "Failed to update reading status.");
          Diagnostics.error("sync.status.update.failure", {
            mangaId: targetMangaId,
            status: status,
            requestId: errorObj?.requestId || "",
            message: errorObj?.message || "",
            statusCode: Number(errorObj?.status || 0)
          }, "Failed to update manga reading status");
        }
      ,
      createApiRequestOptions("status-update", {
        mangaId: targetMangaId,
        status: status
      }));
    });
  }

  // --------------------
  // Display helpers for panel
  // --------------------
  function mangaTitle(manga) {
    return ReaderService.mangaTitle(manga, preferredLanguage);
  }

  function mangaDescription(manga) {
    return ReaderService.mangaDescription(manga, preferredLanguage);
  }

  function chapterLabel(chapter) {
    return ReaderService.chapterLabel(chapter);
  }
}
