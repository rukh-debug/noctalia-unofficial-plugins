var MODE_OFF = "off";
var MODE_NORMAL = "normal";
var MODE_VERBOSE = "verbose";

var _mode = MODE_NORMAL;
var _sink = null;
var _prefix = "MangaDex";

function normalizeMode(modeValue) {
    var normalized = String(modeValue || "").toLowerCase().trim();
    if (normalized === MODE_OFF || normalized === MODE_VERBOSE) {
        return normalized;
    }
    return MODE_NORMAL;
}

function configure(options) {
    if (!options || typeof options !== "object") {
        return;
    }

    if (typeof options.sink === "function") {
        _sink = options.sink;
    }

    if (options.prefix !== undefined && options.prefix !== null && String(options.prefix).trim() !== "") {
        _prefix = String(options.prefix).trim();
    }

    if (options.mode !== undefined) {
        _mode = normalizeMode(options.mode);
    }
}

function setMode(modeValue) {
    _mode = normalizeMode(modeValue);
}

function getMode() {
    return _mode;
}

function isVerbose() {
    return _mode === MODE_VERBOSE;
}

function _isAllowed(level, severity) {
    if (severity === "error") {
        return true;
    }

    if (_mode === MODE_OFF) {
        return false;
    }

    if (_mode === MODE_NORMAL && level === MODE_VERBOSE) {
        return false;
    }

    return true;
}

function _safeStringify(value) {
    if (value === undefined || value === null) {
        return "";
    }

    try {
        return JSON.stringify(value);
    } catch (e) {
        return "{\"serialization\":\"failed\"}";
    }
}

function _emit(severity, level, eventName, context, message) {
    if (!_isAllowed(level, severity)) {
        return;
    }

    var event = eventName || "event";
    var payload = context && typeof context === "object" ? context : {};
    var text = "[" + _prefix + "][" + String(severity || "info").toUpperCase() + "][" + event + "]";

    if (message !== undefined && message !== null && String(message).trim() !== "") {
        text += " " + String(message);
    }

    var payloadText = _safeStringify(payload);
    if (payloadText !== "" && payloadText !== "{}") {
        text += " " + payloadText;
    }

    if (typeof _sink === "function") {
        _sink(severity, text, event, payload, message || "");
        return;
    }

    if (typeof console !== "undefined" && typeof console.log === "function") {
        console.log(text);
    }
}

function debug(eventName, context, message) {
    _emit("debug", MODE_VERBOSE, eventName, context, message);
}

function info(eventName, context, message) {
    _emit("info", MODE_NORMAL, eventName, context, message);
}

function warn(eventName, context, message) {
    _emit("warn", MODE_NORMAL, eventName, context, message);
}

function error(eventName, context, message) {
    _emit("error", MODE_NORMAL, eventName, context, message);
}

function childContext(baseContext, extraContext) {
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
