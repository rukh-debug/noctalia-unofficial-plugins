import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import "ProviderLogic.js" as ProviderLogic

Item {
  id: root

  property var pluginApi: null

  // State
  property var messages: []
  property bool isGenerating: false
  property string currentResponse: ""
  property string errorMessage: ""
  property bool isManuallyStopped: false
  property string currentChatId: "" // Track current chat for context

  // Save state when currentChatId changes
  onCurrentChatIdChanged: {
    saveState();
  }

  // Signals
  signal titleUpdated()

  // Cache directory for state (messages)
  readonly property string cacheDir: typeof Settings !== 'undefined' && Settings.cacheDir ? Settings.cacheDir + "plugins/openwebui-launcher/" : ""
  readonly property string stateCachePath: cacheDir + "state.json"

  // Settings accessors
  readonly property string baseUrl: pluginApi?.pluginSettings?.baseUrl || pluginApi?.manifest?.metadata?.defaultSettings?.baseUrl || ""
  readonly property string apiToken: pluginApi?.pluginSettings?.apiToken || pluginApi?.manifest?.metadata?.defaultSettings?.apiToken || ""
  readonly property string currentModel: pluginApi?.pluginSettings?.defaultModel || pluginApi?.manifest?.metadata?.defaultSettings?.defaultModel || ""
  readonly property bool rememberHistory: pluginApi?.pluginSettings?.rememberHistory ?? pluginApi?.manifest?.metadata?.defaultSettings?.rememberHistory ?? true

  Component.onCompleted: {
    Logger.i("OpenWebUI", "Plugin initialized");
    ensureCacheDir();
  }

  // Ensure cache directory exists
  function ensureCacheDir() {
    if (cacheDir) {
      Quickshell.execDetached(["mkdir", "-p", cacheDir]);
    }
  }

  // FileView for state cache (messages)
  FileView {
    id: stateCacheFile
    path: root.stateCachePath
    watchChanges: false

    onLoaded: {
      loadStateFromCache();
    }

    onLoadFailed: function (error) {
      if (error === 2) {
        Logger.d("OpenWebUI", "No cache file found, starting fresh");
      } else {
        Logger.e("OpenWebUI", "Failed to load state cache: " + error);
      }
    }
  }

  // Load state from cache file
  function loadStateFromCache() {
    if (!rememberHistory) {
      Logger.d("OpenWebUI", "Remember history disabled, skipping cache load");
      return;
    }

    try {
      var content = stateCacheFile.text();
      if (!content || content.trim() === "") {
        Logger.d("OpenWebUI", "Empty cache file, starting fresh");
        return;
      }

      var cached = JSON.parse(content);
      root.messages = cached.messages || [];
      root.currentChatId = cached.currentChatId || "";
      Logger.d("OpenWebUI", "Loaded " + root.messages.length + " messages and chat ID '" + root.currentChatId + "' from cache");
    } catch (e) {
      Logger.e("OpenWebUI", "Failed to parse state cache: " + e);
    }
  }

  // Debounced save timer
  Timer {
    id: saveStateTimer
    interval: 500
    onTriggered: performSaveState()
  }

  property bool saveStateQueued: false

  function saveState() {
    if (!rememberHistory) return;
    saveStateQueued = true;
    saveStateTimer.restart();
  }

  function performSaveState() {
    if (!saveStateQueued || !cacheDir || !rememberHistory)
      return;
    saveStateQueued = false;

    try {
      ensureCacheDir();

      var maxHistory = pluginApi?.pluginSettings?.maxHistoryLength || 100;
      var toSave = root.messages.slice(-maxHistory);

      var stateData = {
        messages: toSave,
        currentChatId: root.currentChatId,
        timestamp: Math.floor(Date.now() / 1000)
      };

      stateCacheFile.setText(JSON.stringify(stateData, null, 2));
      Logger.d("OpenWebUI", "Saved " + toSave.length + " messages and chat ID '" + root.currentChatId + "' to cache");
    } catch (e) {
      Logger.e("OpenWebUI", "Failed to save state cache: " + e);
    }
  }

  // Add a message to the chat
  function addMessage(role, content) {
    var newMessage = {
      "id": Date.now().toString(),
      "role": role,
      "content": content,
      "timestamp": Math.floor(Date.now() / 1000)
    };
    root.messages = [...root.messages, newMessage];
    saveState();
    return newMessage;
  }

  // Clear chat history
  function clearMessages() {
    root.messages = [];
    root.currentChatId = "";
    saveState();
    Logger.i("OpenWebUI", "Chat history cleared");
  }

  // Send a message to OpenWebUI
  function sendMessage(userMessage) {
    Logger.i("OpenWebUI", "sendMessage called with: " + userMessage);
    if (!userMessage || userMessage.trim() === "") {
      Logger.i("OpenWebUI", "sendMessage: empty message, abort");
      return;
    }
    if (root.isGenerating) {
      Logger.i("OpenWebUI", "sendMessage: already generating, abort");
      return;
    }

    if (!baseUrl || baseUrl.trim() === "") {
      root.errorMessage = "Please configure your OpenWebUI base URL in settings";
      Logger.e("OpenWebUI", "sendMessage: missing base URL");
      ToastService.showError(root.errorMessage);
      return;
    }

    if (!apiToken || apiToken.trim() === "") {
      root.errorMessage = "Please configure your API token in settings";
      Logger.e("OpenWebUI", "sendMessage: missing API token");
      ToastService.showError(root.errorMessage);
      return;
    }

    Logger.i("OpenWebUI", "Adding user message and starting generation");
    addMessage("user", userMessage.trim());

    root.isGenerating = true;
    root.isManuallyStopped = false;
    root.currentResponse = "";
    root.errorMessage = "";

    sendOpenWebUIRequest();
  }

  // Stop generation
  function stopGeneration() {
    if (!root.isGenerating)
      return;
    Logger.i("OpenWebUI", "Stopping generation");

    root.isManuallyStopped = true;
    if (openwebuiProcess.running)
      openwebuiProcess.running = false;

    root.isGenerating = false;
    // If we have a partial response, add it to chat history
    if (root.currentResponse.trim() !== "") {
      root.addMessage("assistant", root.currentResponse.trim());
    }
    root.currentResponse = "";
  }

  // Build conversation history for API (includes chat context)
  function buildConversationHistory() {
    var history = [];
    for (var i = 0; i < root.messages.length; i++) {
      var msg = root.messages[i];
      history.push({
        "role": msg.role,
        "content": msg.content
      });
    }
    return history;
  }

  // =====================
  // OpenWebUI API
  // =====================
  Process {
    id: openwebuiProcess

    property string buffer: ""

    stdout: SplitParser {
      onRead: function (data) {
        openwebuiProcess.handleStreamData(data);
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim() !== "") {
          Logger.e("OpenWebUI", "curl stderr: " + text);
        }
      }
    }

    function handleStreamData(data) {
      if (!data)
        return;
      var line = data.trim();
      if (line === "")
        return;

      // Standard SSE Stream
      if (line.startsWith("data: ")) {
        var jsonStr = line.substring(6).trim();
        if (jsonStr === "[DONE]")
          return;
        try {
          var json = JSON.parse(jsonStr);
          if (json.choices && json.choices[0]) {
            if (json.choices[0].delta && json.choices[0].delta.content) {
              root.currentResponse += json.choices[0].delta.content;
            } else if (json.choices[0].message && json.choices[0].message.content) {
              root.currentResponse = json.choices[0].message.content;
            }
          }
        } catch (e) {
          Logger.e("OpenWebUI", "Error parsing SSE JSON: " + e);
        }
        return;
      }

      // Buffer accumulation for non-SSE data (likely error JSON)
      openwebuiProcess.buffer += line;
      try {
        var errorJson = JSON.parse(openwebuiProcess.buffer);
        if (errorJson.error) {
          root.errorMessage = errorJson.error.message || "API error";
        }
        openwebuiProcess.buffer = "";
      } catch (e) {
        // Incomplete JSON, keep buffering
      }
    }

    onExited: function (exitCode, exitStatus) {
      if (root.isManuallyStopped) {
        root.isManuallyStopped = false;
        return;
      }

      root.isGenerating = false;

      if (exitCode !== 0 && root.currentResponse === "") {
        if (root.errorMessage === "") {
          root.errorMessage = "Request failed. Please check your OpenWebUI connection.";
        }
        return;
      }

      if (root.currentResponse.trim() !== "") {
        root.addMessage("assistant", root.currentResponse.trim());
        
        // Save or update the chat on the server (this will call title generation and background tasks after save)
        root.saveOrUpdateChat();
      }

      openwebuiProcess.buffer = "";
    }
  }

  function sendOpenWebUIRequest() {
    var history = buildConversationHistory();
    var payload = ProviderLogic.buildOpenWebUIPayload(currentModel, history);

    var cleanUrl = baseUrl.replace(/\/+$/, "");
    var endpoint = cleanUrl + "/api/v1/chat/completions";

    Logger.i("OpenWebUI", "sendOpenWebUIRequest: endpoint=" + endpoint);
    Logger.i("OpenWebUI", "sendOpenWebUIRequest: payload=" + JSON.stringify(payload));
    Logger.i("OpenWebUI", "sendOpenWebUIRequest: currentChatId=" + currentChatId);
    openwebuiProcess.buffer = "";

    var cmd = ["curl", "-s", "-S", "--no-buffer", "-X", "POST", "-H", "Content-Type: application/json"];

    if (apiToken && apiToken.trim() !== "") {
      cmd.push("-H", "Authorization: Bearer " + apiToken);
    }
    
    // Add chat_id to payload if we're in an existing chat context
    if (currentChatId && currentChatId !== "") {
      payload.chat_id = currentChatId;
      Logger.i("OpenWebUI", "Including chat_id in request: " + currentChatId);
    }

    cmd.push("-d", JSON.stringify(payload));
    cmd.push(endpoint);

    openwebuiProcess.command = cmd;
    Logger.i("OpenWebUI", "sendOpenWebUIRequest: starting process");
    openwebuiProcess.running = true;
  }
  
  // Function to create or update chat after a successful message exchange
  function saveOrUpdateChat() {
    if (!baseUrl || !apiToken || root.messages.length === 0) return;
    
    // Build the chat data structure
    var chatData = {
      "title": generateChatTitle(),
      "chat": {
        "id": "",
        "title": generateChatTitle(),
        "models": [currentModel],
        "params": {},
        "history": {
          "messages": {},
          "currentId": null
        },
        "messages": [],
        "tags": [],
        "timestamp": Math.floor(Date.now())
      },
      "folder_id": null
    };
    
    // Build message structure
    var lastId = null;
    for (var i = 0; i < root.messages.length; i++) {
      var msg = root.messages[i];
      var msgId = msg.id || ("msg-" + i);
      
      // Convert timestamp to Unix seconds if needed
      var ts = msg.timestamp;
      if (typeof ts === 'string') {
        var d = new Date(ts);
        if (!isNaN(d.getTime())) {
          ts = Math.floor(d.getTime() / 1000);
        } else {
          ts = Math.floor(Date.now() / 1000);
        }
      } else if (typeof ts === 'number' && ts > 10000000000) {
        // Assume milliseconds if > 10 digits (roughly > year 2286 in seconds, but clearly ms for current dates)
        ts = Math.floor(ts / 1000);
      } else if (!ts) {
        ts = Math.floor(Date.now() / 1000);
      }

      chatData.chat.history.messages[msgId] = {
        "id": msgId,
        "role": msg.role,
        "content": msg.content,
        "timestamp": ts,
        "parentId": lastId,
        "childrenIds": [],
        "models": [currentModel]
      };
      
      // Also add to messages array
      chatData.chat.messages.push({
        "id": msgId,
        "parentId": lastId,
        "childrenIds": [],
        "role": msg.role,
        "content": msg.content,
        "timestamp": ts,
        "models": [currentModel]
      });
      
      lastId = msgId;
    }
    chatData.chat.history.currentId = lastId;
    
    var xhr = new XMLHttpRequest();
    var cleanUrl = baseUrl.replace(/\/+$/, "");
    var endpoint;
    var method;
    
    if (currentChatId && currentChatId !== "") {
      // Update existing chat
      endpoint = cleanUrl + "/api/v1/chats/" + currentChatId;
      method = "POST";
      Logger.i("OpenWebUI", "Updating chat: " + currentChatId);
    } else {
      // Create new chat
      endpoint = cleanUrl + "/api/v1/chats/new";
      method = "POST";
      Logger.i("OpenWebUI", "Creating new chat");
    }
    
    xhr.open(method, endpoint);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("Authorization", "Bearer " + apiToken);
    
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status >= 200 && xhr.status < 300) {
          try {
            var resp = JSON.parse(xhr.responseText);
            if (resp.id) {
              currentChatId = resp.id;
              Logger.i("OpenWebUI", "Chat saved with ID: " + currentChatId);
              
              // Now that we have the chat ID, generate title if this is the first exchange
              if (root.messages.length === 2) {
                  root.generateAndUpdateTitleRemote();
              }
            }
          } catch (e) {
            Logger.e("OpenWebUI", "Failed to parse save chat response: " + e);
          }
        } else {
          Logger.e("OpenWebUI", "Failed to save chat: " + xhr.status);
        }
      }
    };
    
    xhr.send(JSON.stringify(chatData));
  }
  
  function generateChatTitle() {
    // Generate a title from the first user message
    for (var i = 0; i < root.messages.length; i++) {
      if (root.messages[i].role === "user") {
        var content = root.messages[i].content;
        if (content.length > 50) {
          return content.substring(0, 47) + "...";
        }
        return content;
      }
    }
    return "New Chat";
  }

  function generateAndUpdateTitleRemote() {
    if (!baseUrl || !apiToken) return;
    if (!currentChatId) {
        Logger.w("OpenWebUI", "Cannot generate title without chat ID");
        return;
    }
    
    // Only generate if we have at least 2 messages (user + assistant)
    if (root.messages.length < 2) return;

    var xhr = new XMLHttpRequest();
    var cleanUrl = baseUrl.replace(/\/+$/, "");
    var endpoint = cleanUrl + "/api/v1/tasks/title/completions";
    
    // Prepare relevant messages (first user and first assistant)
    var relevantMessages = [];
    // Find first user message
    var firstUserMsg = null;
    for (var i = 0; i < root.messages.length; i++) {
        if (root.messages[i].role === "user") {
            firstUserMsg = root.messages[i];
            break;
        }
    }
    // Find first assistant message (usually the next one)
    var firstAssistantMsg = null;
    for (var j = 0; j < root.messages.length; j++) {
        if (root.messages[j].role === "assistant" && (!firstUserMsg || j > i)) {
            firstAssistantMsg = root.messages[j];
            break;
        }
    }
    
    if (firstUserMsg && firstAssistantMsg) {
        relevantMessages.push({ "role": firstUserMsg.role, "content": firstUserMsg.content });
        relevantMessages.push({ "role": firstAssistantMsg.role, "content": firstAssistantMsg.content });
    } else {
        // Fallback: just take first 2
        if (root.messages.length >= 2) {
             relevantMessages.push({ "role": root.messages[0].role, "content": root.messages[0].content });
             relevantMessages.push({ "role": root.messages[1].role, "content": root.messages[1].content });
        } else {
            return;
        }
    }

    var payload = {
      "model": currentModel,
      "messages": relevantMessages
    };
    
    xhr.open("POST", endpoint);
    xhr.setRequestHeader("Content-Type", "application/json");
    if (apiToken) {
        xhr.setRequestHeader("Authorization", "Bearer " + apiToken);
    }
    
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status === 200) {
          try {
            var response = JSON.parse(xhr.responseText);
            if (response.choices && response.choices.length > 0) {
              var contentStr = response.choices[0].message.content;
              var title = "";
              
              // Helper to clean title
              var cleanTitle = function(t) {
                  return t.replace(/^["']|["']$/g, "").trim();
              };

              // Try parsing content as JSON first (as seen in test: "{\"title\": ...}")
              try {
                var contentJson = JSON.parse(contentStr);
                if (contentJson && contentJson.title) {
                  title = cleanTitle(contentJson.title);
                } else {
                  title = cleanTitle(contentStr);
                }
              } catch (e) {
                // JSON parsing failed - try to extract title with regex
                var titleMatch = contentStr.match(/"title"\s*:\s*"([^"]*)"/);
                if (titleMatch && titleMatch[1]) {
                  title = titleMatch[1];
                } else {
                  // Last resort: use raw content
                  title = cleanTitle(contentStr);
                }
              }
              
              if (title && title.length > 0) {
                Logger.i("OpenWebUI", "Generated remote title: " + title);
                root.updateChatTitle(title);
              }
            }
          } catch (e) {
            Logger.e("OpenWebUI", "Error parsing title response: " + e);
          }
        } else {
            Logger.e("OpenWebUI", "Title generation failed: " + xhr.status + " " + xhr.responseText);
        }
      }
    };
    
    xhr.send(JSON.stringify(payload));
  }

  function updateChatTitle(newTitle) {
    if (!baseUrl || !apiToken || !currentChatId) {
        Logger.w("OpenWebUI", "Cannot update title: missing parameters");
        return;
    }

    var xhr = new XMLHttpRequest();
    var cleanUrl = baseUrl.replace(/\/+$/, "");
    var endpoint = cleanUrl + "/api/v1/chats/" + currentChatId;

    // Build the chat update payload with the new title
    var chatData = {
      "title": newTitle,
      "chat": {
        "id": currentChatId || "",
        "title": newTitle,
        "models": [currentModel],
        "params": {},
        "history": {
          "messages": {},
          "currentId": null
        },
        "messages": [],
        "tags": [],
        "timestamp": Math.floor(Date.now())
      },
      "folder_id": null
    };

    // Build message structure
    var lastId = null;
    for (var i = 0; i < root.messages.length; i++) {
      var msg = root.messages[i];
      var msgId = msg.id || ("msg-" + i);
      
      // Convert timestamp to Unix seconds if needed
      var ts = msg.timestamp;
      if (typeof ts === 'string') {
        var d = new Date(ts);
        if (!isNaN(d.getTime())) {
          ts = Math.floor(d.getTime() / 1000);
        } else {
          ts = Math.floor(Date.now() / 1000);
        }
      } else if (typeof ts === 'number' && ts > 10000000000) {
        ts = Math.floor(ts / 1000);
      } else if (!ts) {
        ts = Math.floor(Date.now() / 1000);
      }

      chatData.chat.history.messages[msgId] = {
        "id": msgId,
        "role": msg.role,
        "content": msg.content,
        "timestamp": ts,
        "parentId": lastId,
        "childrenIds": [],
        "models": [currentModel]
      };
      
      // Also add to messages array
      chatData.chat.messages.push({
        "id": msgId,
        "parentId": lastId,
        "childrenIds": [],
        "role": msg.role,
        "content": msg.content,
        "timestamp": ts,
        "models": [currentModel]
      });
      
      lastId = msgId;
    }
    chatData.chat.history.currentId = lastId;

    xhr.open("POST", endpoint);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("Authorization", "Bearer " + apiToken);
    
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status >= 200 && xhr.status < 300) {
          Logger.i("OpenWebUI", "Chat title updated successfully to: " + newTitle);
          // Notify panel to refresh sidebar
          root.titleUpdated();
        } else {
          Logger.e("OpenWebUI", "Failed to update chat title: " + xhr.status + " " + xhr.responseText);
        }
      }
    };
    
    xhr.send(JSON.stringify(chatData));
  }

  // =====================
  // IPC Handlers
  // =====================
  IpcHandler {
    target: "plugin:openwebui-launcher"

    function toggle() {
      if (!pluginApi) return;
      pluginApi.withCurrentScreen(screen => {
        pluginApi.togglePanel(screen);
      });
    }

    function open() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.openPanel(screen);
        });
      }
    }

    function close() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.closePanel(screen);
        });
      }
    }

    function send(message: string) {
      if (message && message.trim() !== "") {
        root.sendMessage(message);
        ToastService.showNotice("Message sent");
      }
    }

    function clear() {
      root.clearMessages();
      ToastService.showNotice("Chat history cleared");
    }

    function setModel(modelName: string) {
      if (pluginApi && modelName) {
        if (!pluginApi.pluginSettings)
          pluginApi.pluginSettings = {};
        pluginApi.pluginSettings.defaultModel = modelName;
        pluginApi.saveSettings();
        ToastService.showNotice("Model changed to " + modelName);
      }
    }
  }
}
