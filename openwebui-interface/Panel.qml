import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets
import "components"
import "ApiService.js" as ApiService

Item {
  id: root
  property var pluginApi: null

  readonly property var settings: pluginApi?.pluginSettings || {}
  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || {}

  readonly property string baseUrl: settings.baseUrl || defaults.baseUrl || ""
  readonly property string apiToken: settings.apiToken || defaults.apiToken || ""
  readonly property bool hasToken: !!apiToken

  readonly property string defaultModel: settings.defaultModel || defaults.defaultModel || ""
  property string currentModel: defaultModel
  property real panelWidth: settings.panelWidth || defaults.panelWidth || 900
  property real panelHeight: settings.panelHeight || defaults.panelHeight || 560
  readonly property string panelPosition: settings.panelPosition || defaults.panelPosition || "bottom"
  
  // Chat management state
  property var chatList: []
  property bool fetchingChats: false
  property string chatsError: ""
  property string currentChatId: mainInstance?.currentChatId || "" // Sync from main instance
  property var currentChatData: null
  property bool loadingChat: false
  property bool sidebarVisible: true
  property int currentPage: 1
  property bool hasMoreChats: true

  // State from main instance
  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property var messages: mainInstance?.messages || []
  readonly property bool isGenerating: mainInstance?.isGenerating || false
  readonly property string currentResponse: mainInstance?.currentResponse || ""
  readonly property string errorMessage: mainInstance?.errorMessage || ""
  
  // Sync chat ID from main instance
  Connections {
    target: mainInstance
    enabled: mainInstance !== null
    
    function onCurrentChatIdChanged() {
      if (mainInstance && mainInstance.currentChatId !== currentChatId) {
        currentChatId = mainInstance.currentChatId;
        // Refresh chat list when a new chat is created or title is updated
        if (currentChatId !== "" && hasToken && baseUrl) {
          Qt.callLater(refreshChatList);
        }
      }
    }
  }

  property var availableModels: []
  property bool fetchingModels: false
  property string modelsError: ""
  property bool showModelSelector: false

  readonly property real contentPreferredWidth: panelWidth * Style.uiScaleRatio
  readonly property real contentPreferredHeight: panelHeight * Style.uiScaleRatio
  readonly property bool allowAttach: true
  
  // Calculate anchoring based on position
  readonly property bool panelAnchorTop: panelPosition.startsWith("top")
  readonly property bool panelAnchorBottom: panelPosition.startsWith("bottom")
  readonly property bool panelAnchorLeft: panelPosition.includes("left") || panelPosition === "left"
  readonly property bool panelAnchorRight: panelPosition.includes("right") || panelPosition === "right"
  readonly property bool panelAnchorHCenter: panelPosition === "top" || panelPosition === "bottom"
  readonly property bool panelAnchorVCenter: panelPosition === "left" || panelPosition === "right"

  function fetchChatList(page) {
    if (fetchingChats || !baseUrl || !apiToken || !hasMoreChats) return;
    
    var pageNum = page || 1;
    fetchingChats = true;
    chatsError = "";
    
    ApiService.fetchChatList(
      baseUrl,
      apiToken,
      pageNum,
      function(resp) {
        fetchingChats = false;
        if (pageNum === 1) {
          chatList = resp;
        } else {
          chatList = chatList.concat(resp);
        }
        hasMoreChats = resp.length > 0;
        currentPage = pageNum;
        Logger.i("OpenWebUI", "Loaded page " + pageNum + ", " + resp.length + " chats (total: " + chatList.length + ")");
      },
      function(error) {
        fetchingChats = false;
        chatsError = error;
        Logger.e("OpenWebUI", error);
      }
    );
  }
  
  function loadMoreChats() {
    if (!fetchingChats && hasMoreChats) {
      fetchChatList(currentPage + 1);
    }
  }
  
  function refreshChatList() {
    currentPage = 1;
    hasMoreChats = true;
    fetchChatList(1);
  }
  
  function loadChatById(chatId) {
    if (loadingChat || !baseUrl || !apiToken || !chatId) return;
    
    loadingChat = true;
    
    ApiService.loadChatById(
      baseUrl,
      apiToken,
      chatId,
      function(resp) {
        loadingChat = false;
        currentChatData = resp;
        currentChatId = chatId;
        
        // Sync chat ID to Main instance
        if (mainInstance) {
          mainInstance.currentChatId = chatId;
        }
        
        // Extract messages from chat history
        if (mainInstance && resp.chat && resp.chat.history && resp.chat.history.messages) {
          var messages = [];
          var msgMap = resp.chat.history.messages;
          var currentId = resp.chat.history.currentId;
          
          // Traverse from currentId backwards
          var visited = {};
          var id = currentId;
          while (id && msgMap[id] && !visited[id]) {
            visited[id] = true;
            var msg = msgMap[id];
            messages.unshift({
              "id": id,
              "role": msg.role,
              "content": msg.content,
              "read": true,
              "timestamp": msg.timestamp || ""
            });
            id = msg.parentId || null;
          }
          
          mainInstance.messages = messages;
          Logger.i("OpenWebUI", "Loaded " + messages.length + " messages from chat " + chatId);
        } else {
          Logger.e("OpenWebUI", "Invalid chat data structure");
          ToastService.showError("Failed to load chat messages");
        }
      },
      function(error) {
        loadingChat = false;
        Logger.e("OpenWebUI", error);
        ToastService.showError("Failed to load chat");
      }
    );
  }
  
  function startNewChat() {
    currentChatId = "";
    currentChatData = null;
    if (mainInstance) {
      mainInstance.currentChatId = "";
      mainInstance.clearMessages();
    }
    ToastService.showNotice("Started new chat");
  }
  
  function fetchModels() {
    if (fetchingModels || !baseUrl || !apiToken) return;
    
    fetchingModels = true;
    modelsError = "";
    
    ApiService.fetchModels(
      baseUrl,
      apiToken,
      function(models) {
        fetchingModels = false;
        availableModels = models;
        
        // Set first model as default if current model is empty
        if (models.length > 0 && !currentModel) {
          currentModel = models[0];
        }
      },
      function(error) {
        fetchingModels = false;
        modelsError = error;
        Logger.e("OpenWebUI", error);
      }
    );
  }

  function sendMessage(text) {
    if (text === "" || !mainInstance)
      return;
    mainInstance.sendMessage(text);
  }

  Rectangle {
    anchors.fill: parent
    color: "transparent"

    // AUTH REQUIRED VIEW
    AuthRequiredView {
      visible: !hasToken
    }

    // CHAT VIEW WITH SIDEBAR
    RowLayout {
      anchors.fill: parent
      spacing: 0
      visible: hasToken
      
      // Sidebar Component
      Sidebar {
        id: sidebar
        Layout.preferredWidth: sidebarVisible ? 280 : 0
        Layout.fillHeight: true
        
        visible: sidebarVisible
        // Animation for width change
        Behavior on Layout.preferredWidth {
           NumberAnimation { duration: Style.animationNormal }
        }
        
        chatList: root.chatList
        currentChatId: root.currentChatId
        fetchingChats: root.fetchingChats
        chatsError: root.chatsError
        
        onChatSelected: (chatId) => loadChatById(chatId)
        onNewChatRequested: () => startNewChat()
        onRefreshRequested: () => refreshChatList()
        onLoadMoreRequested: () => loadMoreChats()
      }
      
      // Divider
      Rectangle {
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        color: Style.capsuleBorderColor
        visible: sidebarVisible
      }
      
      // Main chat area
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.marginM

        anchors.margins: Style.marginL
        
        // Header with sidebar toggle and model info
        HeaderBar {
          Layout.fillWidth: true
          
          sidebarVisible: root.sidebarVisible
          currentModel: root.currentModel
          defaultModel: root.defaultModel
          pluginApi: root.pluginApi
          chatData: root.currentChatData
          
          availableModels: root.availableModels
          fetchingModels: root.fetchingModels
          modelsError: root.modelsError
          
          onSidebarToggled: root.sidebarVisible = !root.sidebarVisible
          onSetDefaultModel: (model) => {
            if (pluginApi && model) {
              pluginApi.pluginSettings.defaultModel = model;
              pluginApi.saveSettings();
              ToastService.showNotice("Default model set to: " + model);
            }
          }
          onOpenModelSelector: {
            if (availableModels.length === 0) {
              fetchModels();
            }
            modelSelectorPopup.open();
          }
        }
        
        // Model selector popup
        ModelSelector {
          id: modelSelectorPopup
          parent: Overlay.overlay
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2
          width: 300
          
          availableModels: root.availableModels
          currentModel: root.currentModel
          fetchingModels: root.fetchingModels
          modelsError: root.modelsError
          
          onModelSelected: (model) => root.currentModel = model
        }

        NIcon {
          icon: "loader-2"
          visible: isGenerating
          color: Color.mPrimary
          pointSize: Style.fontSizeS

          RotationAnimation on rotation {
            from: 0
            to: 360
            duration: 1000
            loops: Animation.Infinite
            running: isGenerating
          }
        }
      
        // Chat Area
        ChatArea {
          Layout.fillWidth: true
          Layout.fillHeight: true
          
          messages: root.messages
          currentChatId: root.currentChatId
          isGenerating: root.isGenerating
          loadingChat: root.loadingChat
          currentResponse: root.currentResponse
          pluginApi: root.pluginApi
        }

        // Error message
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: errorRow.implicitHeight + Style.marginS * 2
          color: Qt.alpha(Color.mError, 0.2)
          radius: Style.radiusS
          visible: errorMessage !== ""

          RowLayout {
            id: errorRow
            anchors.fill: parent
            anchors.margins: Style.marginS
            spacing: Style.marginS

            NIcon {
              icon: "alert-triangle"
              color: Color.mError
              pointSize: Style.fontSizeM
            }

            TextEdit {
              Layout.fillWidth: true
              text: errorMessage
              color: Color.mError
              font.pointSize: Style.fontSizeS
              wrapMode: TextEdit.Wrap
              readOnly: true
              selectByMouse: true
            }
          }
        }

        // Input Area
        InputArea {
            id: inputArea
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            
            isGenerating: root.isGenerating
            
            onMessageSent: (text) => sendMessage(text)
            onStopRequested: () => {
                if (mainInstance) mainInstance.stopGeneration()
            }
        }
      }
    }
  }

  Component.onCompleted: {
    if (hasToken && baseUrl) {
      fetchModels();
      fetchChatList(1);
      if (currentModel) {
        fetchModelMetadata(currentModel);
      }
    }
  }

  // Reload data when panel becomes visible
  onVisibleChanged: {
    // Keep mainInstance in sync so it knows whether to auto-open
    if (mainInstance) {
      mainInstance.isPanelVisible = visible;
    }

    if (visible && hasToken && baseUrl) {
      // Sync currentChatId from main instance (in case it was loaded from cache)
      if (mainInstance && mainInstance.currentChatId && mainInstance.currentChatId !== currentChatId) {
        currentChatId = mainInstance.currentChatId;
      }
      
      fetchChatList(1);
      
      // If we have a currentChatId (from cache or previous session), keep showing it
      // Don't reload it if messages already exist to avoid unnecessary API calls
      if (currentChatId && mainInstance && mainInstance.messages.length === 0) {
        loadChatById(currentChatId);
      }
    }
  }

  // Fetch models and chats when authentication status changes
  onHasTokenChanged: {
    if (hasToken && baseUrl) {
      fetchModels();
      fetchChatList(1);
    }
  }

  // Safe focusInput method for parent to call
  function focusInput() {
    if (typeof inputArea !== 'undefined' && inputArea && inputArea.focusInput) {
      inputArea.focusInput();
    }
  }
}
