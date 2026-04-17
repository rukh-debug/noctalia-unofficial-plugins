// crypto-helper.js — Lazy-loads node-forge v1.0.0 (CDN + disk cache)
// https://github.com/digitalbazaar/forge (BSD-3-Clause License)
//
// Pure ES5 — no polyfills needed. forge uses binary strings internally.
//
// Load order:
//   1. Try disk cache (file:// XHR, synchronous)
//   2. Fall back to CDN download (jsdelivr, synchronous XHR)
//   3. Store CDN content for Main.qml to persist to disk

var CryptoHelper = (function() {
    var _forge = null;
    var _CDN_URL = "https://cdn.jsdelivr.net/npm/node-forge@1.0.0/dist/forge.min.js";
    var _cacheDir = "";
    var _pendingCache = null; // CDN source text, waiting to be written to disk

    // Lazy-load forge: cache → CDN
    function _ensureForge() {
        if (_forge) return _forge;

        // --- Try disk cache first ---
        if (_cacheDir) {
            try {
                var cacheXhr = new XMLHttpRequest();
                cacheXhr.open("GET", "file://" + _cacheDir + "forge.cache.js", false);
                cacheXhr.send();
                if (cacheXhr.status === 200 && cacheXhr.responseText
                    && cacheXhr.responseText.length > 10000) {
                    if (typeof window === "undefined") var window = {};
                    eval(cacheXhr.responseText);
                    if (window.forge) {
                        _forge = window.forge;
                        console.log("[Crypto] Loaded forge from disk cache");
                        return _forge;
                    }
                }
            } catch (e) {
                // Cache miss — fall through to CDN
            }
        }

        // --- CDN fallback ---
        var xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", _CDN_URL, false); // synchronous
            xhr.send();
        } catch (e) {
            throw new Error("Failed to fetch crypto library. Check internet connection.");
        }
        if (xhr.status !== 200) {
            throw new Error("Failed to load crypto library: HTTP " + xhr.status);
        }

        if (typeof window === "undefined") var window = {};
        try {
            eval(xhr.responseText);
        } catch (e) {
            throw new Error("Crypto library failed to initialize: " + e);
        }

        _forge = window.forge;
        if (!_forge) throw new Error("Crypto library failed to initialize");

        _pendingCache = true;
        console.log("[Crypto] Loaded forge from CDN (" + Math.round(xhr.responseText.length / 1024) + "KB)");
        return _forge;
    }

    // Convert Uint8Array → forge binary string
    function _b2s(bytes) {
        var s = "";
        for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
        return s;
    }

    // Convert forge binary string → Uint8Array
    function _s2b(str) {
        var bytes = new Uint8Array(str.length);
        for (var i = 0; i < str.length; i++) bytes[i] = str.charCodeAt(i) & 0xFF;
        return bytes;
    }

    return {
        // Set cache directory (called from providers.js init)
        init: function(cacheDir) { _cacheDir = cacheDir || ""; },

        // Trigger forge loading (for eager init from Main.qml)
        ensureLoaded: function() { _ensureForge(); },

        // Returns true if CDN was used and cache file should be created
        needsCacheWrite: function() { return _pendingCache; },

        // CDN URL for external caching (e.g., curl download)
        cdnUrl: function() { return _CDN_URL; },

        // Mark cache as written
        markCacheWritten: function() { _pendingCache = false; },

        // SHA-256 hash: Uint8Array → Uint8Array
        sha256: function(input) {
            var f = _ensureForge();
            var md = f.md.sha256.create();
            md.update(_b2s(input));
            return _s2b(md.digest().getBytes());
        },

        // AES-256-GCM decrypt: (key: Uint8Array, raw: Uint8Array [IV + ciphertext + tag]) → Uint8Array
        aesGcmDecrypt: function(keyBytes, rawBytes) {
            var f = _ensureForge();
            var raw = _b2s(rawBytes);
            var iv = raw.substring(0, 12);
            var tag = raw.substring(raw.length - 16);
            var ciphertext = raw.substring(12, raw.length - 16);

            var decipher = f.cipher.createDecipher("AES-GCM", _b2s(keyBytes));
            decipher.start({ iv: iv, tag: f.util.createBuffer(tag) });
            decipher.update(f.util.createBuffer(ciphertext));
            var pass = decipher.finish();
            if (!pass) throw new Error("aes/gcm: authentication tag mismatch");
            return _s2b(decipher.output.getBytes());
        },

        // Base64 → Uint8Array
        base64Decode: function(str) {
            var f = _ensureForge();
            return _s2b(f.util.decode64(str));
        },

        // Uint8Array → base64
        base64Encode: function(bytes) {
            var f = _ensureForge();
            return f.util.encode64(_b2s(bytes));
        },

        // Hex string → Uint8Array
        hexToBytes: function(hex) {
            var f = _ensureForge();
            return _s2b(f.util.hexToBytes(hex));
        },

        // Uint8Array → hex string
        bytesToHex: function(bytes) {
            var f = _ensureForge();
            return f.util.bytesToHex(_b2s(bytes));
        },

        // Uint8Array → UTF-8 string (binary-safe for ASCII/latin1)
        bytesToString: function(bytes) {
            return _b2s(bytes);
        },

        // Derive key: string → Uint8Array (SHA-256 of reversed string)
        deriveKey: function(secret) {
            var f = _ensureForge();
            var reversed = secret.split("").reverse().join("");
            var md = f.md.sha256.create();
            md.update(reversed);
            return _s2b(md.digest().getBytes());
        }
    };
})();
