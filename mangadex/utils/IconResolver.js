var FALLBACK_ICON = "settings";

var ICON_ALIASES = {
    sliders: "adjustments-horizontal",
    "layout-sidebar-left-expand": "layout-sidebar-right-expand",
    "layout-sidebar-left-collapse": "layout-sidebar-right-collapse"
};

var KNOWN_SAFE_ICONS = {
    "adjustments-horizontal": true,
    "alert-triangle": true,
    "book-2": true,
    "check": true,
    "chevron-left": true,
    "chevron-right": true,
    "chevron-up": true,
    "circle": true,
    "image": true,
    "layout-sidebar-left-expand": true,
    "layout-sidebar-left-collapse": true,
    "layout-sidebar-right-expand": true,
    "layout-sidebar-right-collapse": true,
    "loader-2": true,
    refresh: true,
    "search": true,
    "settings": true,
    "x": true
};

var _warned = {};

function _normalizeKey(value) {
    return String(value || "").toLowerCase().trim();
}

function _warnOnce(key, diagnosticsWarn) {
    if (!key || _warned[key]) {
        return;
    }

    _warned[key] = true;
    if (typeof diagnosticsWarn === "function") {
        diagnosticsWarn("icon.resolve.fallback", {
            requestedIcon: key,
            fallbackIcon: FALLBACK_ICON
        }, "Requested icon was not known-safe; using fallback icon");
    }
}

function resolveIcon(iconName, fallbackIcon, diagnosticsWarn) {
    var requested = _normalizeKey(iconName);
    var fallback = _normalizeKey(fallbackIcon || FALLBACK_ICON) || FALLBACK_ICON;

    if (requested === "") {
        return fallback;
    }

    if (ICON_ALIASES.hasOwnProperty(requested)) {
        requested = ICON_ALIASES[requested];
    }

    if (KNOWN_SAFE_ICONS[requested] === true) {
        return requested;
    }

    _warnOnce(requested, diagnosticsWarn);
    if (KNOWN_SAFE_ICONS[fallback] === true) {
        return fallback;
    }
    return FALLBACK_ICON;
}

function registerKnownIcon(iconName) {
    var key = _normalizeKey(iconName);
    if (key !== "") {
        KNOWN_SAFE_ICONS[key] = true;
    }
}

function resetWarnings() {
    _warned = {};
}
