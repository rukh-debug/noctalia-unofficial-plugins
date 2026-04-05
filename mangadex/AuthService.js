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

var TOKEN_ENDPOINT = "https://auth.mangadex.org/realms/mangadex/protocol/openid-connect/token";
var DEFAULT_TIMEOUT_MS = 20000;
var DEFAULT_MAX_RETRIES = 2;
var DEFAULT_BACKOFF_BASE_MS = 400;

function _encodeForm(formData) {
    var parts = [];
    for (var key in formData) {
        if (!formData.hasOwnProperty(key)) {
            continue;
        }
        var value = formData[key];
        if (value === undefined || value === null) {
            continue;
        }
        parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(value)));
    }
    return parts.join("&");
}

function _extractAuthError(status, responseObj) {
    if (responseObj && typeof responseObj === "object") {
        if (responseObj.error_description) {
            return responseObj.error_description;
        }
        if (responseObj.error) {
            return responseObj.error;
        }
        if (responseObj.message) {
            return responseObj.message;
        }
    }
    return "Authentication failed (HTTP " + status + ")";
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

function _isRetriableStatus(statusValue) {
    var status = Number(statusValue || 0);
    return status === 0 || status === 408 || status === 429 || status === 500 || status === 502 || status === 503 || status === 504;
}

function _schedule(delayMs, timerHost, callback) {
    var waitMs = Math.max(0, Number(delayMs || 0));
    if (waitMs <= 0) {
        callback();
        return;
    }

    if (timerHost && typeof Qt !== "undefined" && typeof Qt.createQmlObject === "function") {
        try {
            var timer = Qt.createQmlObject("import QtQuick; Timer { repeat: false }", timerHost, "MangaDexAuthDelay");
            timer.interval = Math.round(waitMs);
            timer.triggered.connect(function() {
                timer.destroy();
                callback();
            });
            timer.start();
            return;
        } catch (e) {
            _diag("warn", "auth.schedule.fallback", {
                delayMs: waitMs,
                exception: String(e)
            }, "Falling back to immediate auth scheduling");
        }
    }

    callback();
}

function _computeBackoffMs(retryCount, baseDelayMs) {
    var exponent = Math.pow(2, Math.max(0, retryCount));
    return Math.round(baseDelayMs * exponent);
}

function _requestToken(formData, onSuccess, onError, requestOptions) {
    var options = requestOptions && typeof requestOptions === "object" ? requestOptions : {};
    var timerHost = options.timerHost || null;
    var context = options.context && typeof options.context === "object" ? options.context : {};
    var timeoutMs = _safeNumber(options.timeoutMs, DEFAULT_TIMEOUT_MS, 1000, 120000);
    var maxRetries = _safeNumber(options.maxRetries, DEFAULT_MAX_RETRIES, 0, 5);
    var backoffBaseMs = _safeNumber(options.backoffBaseMs, DEFAULT_BACKOFF_BASE_MS, 100, 10000);

    var retryCount = 0;
    var done = false;

    function executeRequest(delayMs) {
        _schedule(delayMs, timerHost, function() {
            if (done) {
                return;
            }

            var attempt = retryCount + 1;
            var xhr = new XMLHttpRequest();
            xhr.timeout = timeoutMs;

            _diag("debug", "auth.request.start", _diagChild(context, {
                endpoint: "token",
                attempt: attempt,
                timeoutMs: timeoutMs
            }), "Sending auth token request");

            try {
                xhr.open("POST", TOKEN_ENDPOINT);
            } catch (openError) {
                handleFailure({
                    status: 0,
                    message: "Failed to initialize authentication request: " + openError
                });
                return;
            }
            xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");

            function handleFailure(errorObj) {
                if (done) {
                    return;
                }

                var enriched = errorObj || {
                    status: 0,
                    message: "Authentication failed"
                };

                if (_isRetriableStatus(enriched.status) && retryCount < maxRetries) {
                    var nextDelayMs = _computeBackoffMs(retryCount, backoffBaseMs);
                    _diag("warn", "auth.request.retry", _diagChild(context, {
                        attempt: attempt,
                        retryCount: retryCount + 1,
                        maxRetries: maxRetries,
                        status: Number(enriched.status || 0),
                        delayMs: nextDelayMs
                    }), "Retrying auth token request");
                    retryCount += 1;
                    executeRequest(nextDelayMs);
                    return;
                }

                _diag("error", "auth.request.failure", _diagChild(context, {
                    attempt: attempt,
                    retriesUsed: retryCount,
                    status: Number(enriched.status || 0),
                    message: enriched.message || ""
                }), "Auth token request failed");

                done = true;
                onError(enriched);
            }

            xhr.onreadystatechange = function() {
                // Use literal readyState value for compatibility across QML runtimes.
                if (xhr.readyState !== 4 || done) {
                    return;
                }

                var payload = null;
                if (xhr.responseText && xhr.responseText.trim() !== "") {
                    try {
                        payload = JSON.parse(xhr.responseText);
                    } catch (parseError) {
                        if (xhr.status >= 200 && xhr.status < 300) {
                            handleFailure({
                                status: xhr.status,
                                message: "Invalid authentication response"
                            });
                            return;
                        }
                    }
                }

                if (xhr.status >= 200 && xhr.status < 300) {
                    if (!payload || !payload.access_token) {
                        handleFailure({
                            status: xhr.status,
                            message: "Authentication response missing access token"
                        });
                        return;
                    }

                    _diag("info", "auth.request.success", _diagChild(context, {
                        attempt: attempt,
                        retriesUsed: retryCount,
                        expiresIn: Number(payload.expires_in || 0)
                    }), "Auth token request succeeded");

                    done = true;
                    onSuccess({
                        accessToken: payload.access_token,
                        refreshToken: payload.refresh_token || "",
                        expiresIn: Number(payload.expires_in || 900),
                        refreshExpiresIn: Number(payload.refresh_expires_in || 0),
                        tokenType: payload.token_type || "Bearer",
                        scope: payload.scope || "",
                        raw: payload
                    });
                    return;
                }

                handleFailure({
                    status: xhr.status,
                    message: _extractAuthError(xhr.status, payload),
                    raw: payload
                });
            };

            xhr.onerror = function() {
                handleFailure({
                    status: 0,
                    message: "Network error while contacting auth.mangadex.org"
                });
            };

            xhr.ontimeout = function() {
                handleFailure({
                    status: 0,
                    message: "Authentication request timed out"
                });
            };

            xhr.send(_encodeForm(formData));
        });
    }

    executeRequest(0);
}

function requestPasswordToken(clientId, clientSecret, username, password, onSuccess, onError, requestOptions) {
    _requestToken({
        grant_type: "password",
        username: username,
        password: password,
        client_id: clientId,
        client_secret: clientSecret
    }, onSuccess, onError, requestOptions);
}

function refreshAccessToken(clientId, clientSecret, refreshToken, onSuccess, onError, requestOptions) {
    _requestToken({
        grant_type: "refresh_token",
        refresh_token: refreshToken,
        client_id: clientId,
        client_secret: clientSecret
    }, onSuccess, onError, requestOptions);
}
