// API Service for OpenWebUI Launcher
// Handles all HTTP requests to OpenWebUI API

.pragma library

function trimmedBaseUrl(baseUrl) {
    return baseUrl ? baseUrl.replace(/\/+$/, "") : "";
}

function fetchChatList(baseUrl, apiToken, page, onSuccess, onError) {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", trimmedBaseUrl(baseUrl) + "/api/v1/chats/?page=" + page);
    xhr.setRequestHeader("Authorization", "Bearer " + apiToken);

    xhr.onreadystatechange = function () {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    var resp = JSON.parse(xhr.responseText);
                    if (Array.isArray(resp)) {
                        onSuccess(resp);
                    } else {
                        onError("Invalid response format");
                    }
                } catch (e) {
                    onError("Failed to parse chats response: " + e);
                }
            } else {
                onError("Failed to fetch chats (" + xhr.status + ")");
            }
        }
    };

    xhr.onerror = function () {
        onError("Network error");
    };

    xhr.send();
}

function loadChatById(baseUrl, apiToken, chatId, onSuccess, onError) {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", trimmedBaseUrl(baseUrl) + "/api/v1/chats/" + chatId);
    xhr.setRequestHeader("Authorization", "Bearer " + apiToken);

    xhr.onreadystatechange = function () {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    var resp = JSON.parse(xhr.responseText);
                    onSuccess(resp);
                } catch (e) {
                    onError("Failed to parse chat: " + e);
                }
            } else {
                onError("Failed to fetch chat: " + xhr.status);
            }
        }
    };

    xhr.onerror = function () {
        onError("Network error loading chat");
    };

    xhr.send();
}

function fetchModels(baseUrl, apiToken, onSuccess, onError) {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", trimmedBaseUrl(baseUrl) + "/api/v1/models");
    xhr.setRequestHeader("Authorization", "Bearer " + apiToken);

    xhr.onreadystatechange = function () {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    var resp = JSON.parse(xhr.responseText);
                    var models = [];

                    // Handle OpenAI-style response
                    if (resp.data && Array.isArray(resp.data)) {
                        models = resp.data.map(function (m) { return m.id || m.name || m; });
                    }
                    // Handle direct array
                    else if (Array.isArray(resp)) {
                        models = resp.map(function (m) { return m.id || m.name || m; });
                    }
                    // Handle models property
                    else if (resp.models && Array.isArray(resp.models)) {
                        models = resp.models.map(function (m) { return m.id || m.name || m; });
                    }

                    onSuccess(models);
                } catch (e) {
                    onError("Failed to parse models response: " + e);
                }
            } else {
                onError("Failed to fetch models (" + xhr.status + ")");
            }
        }
    };

    xhr.onerror = function () {
        onError("Network error");
    };

    xhr.send();
}


