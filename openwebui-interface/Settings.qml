import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets
import qs.Services.UI

ColumnLayout {
  id: root
  property var pluginApi: null

  // Simplify property bindings to match Hello World pattern
  property string valueBaseUrl: pluginApi?.pluginSettings?.baseUrl || pluginApi?.manifest?.metadata?.defaultSettings?.baseUrl || ""
  property string valueToken: pluginApi?.pluginSettings?.apiToken || pluginApi?.manifest?.metadata?.defaultSettings?.apiToken || ""
  property string valueModel: pluginApi?.pluginSettings?.defaultModel || pluginApi?.manifest?.metadata?.defaultSettings?.defaultModel || ""
  property string valuePosition: pluginApi?.pluginSettings?.panelPosition || pluginApi?.manifest?.metadata?.defaultSettings?.panelPosition || "bottom"
  property double valueWidth: pluginApi?.pluginSettings?.panelWidth || pluginApi?.manifest?.metadata?.defaultSettings?.panelWidth || 640
  property double valueHeight: pluginApi?.pluginSettings?.panelHeight || pluginApi?.manifest?.metadata?.defaultSettings?.panelHeight || 560
  property bool valueRememberHistory: pluginApi?.pluginSettings?.rememberHistory ?? pluginApi?.manifest?.metadata?.defaultSettings?.rememberHistory ?? true

  readonly property bool isAuthenticated: valueToken && valueToken.trim() !== ""

  // Auth state properties
  property string authUrlInput: valueBaseUrl || "http://localhost:3000"
  property string authEmailInput: ""
  property string authPassInput: ""
  property string authKeyInput: ""
  property bool loggingIn: false

  // Models state
  property var availableModels: []
  property bool fetchingModels: false
  property string modelsError: ""

  spacing: Style.marginM

  Component.onCompleted: {
    Logger.i("OpenWebUI", "Settings UI loaded");
    if (isAuthenticated) {
      fetchModels();
    }
  }

  // Fetch models when authentication state changes
  onIsAuthenticatedChanged: {
    if (isAuthenticated) {
      Qt.callLater(fetchModels);
    }
  }

  function trimmedBaseUrl() {
    return authUrlInput ? authUrlInput.replace(/\/+$/, "") : "";
  }

  function fetchModels() {
    if (fetchingModels || !valueBaseUrl || !valueToken) return;
    
    fetchingModels = true;
    modelsError = "";
    
    var xhr = new XMLHttpRequest();
    var cleanUrl = valueBaseUrl.replace(/\/+$/, "");
    xhr.open("GET", cleanUrl + "/api/v1/models");
    xhr.setRequestHeader("Authorization", "Bearer " + valueToken);
    
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        fetchingModels = false;
        if (xhr.status >= 200 && xhr.status < 300) {
          try {
            var resp = JSON.parse(xhr.responseText);
            var models = [];
            
            // Handle OpenAI-style response
            if (resp.data && Array.isArray(resp.data)) {
              models = resp.data.map(function(m) { return m.id || m.name || m; });
            } 
            // Handle direct array
            else if (Array.isArray(resp)) {
              models = resp.map(function(m) { return m.id || m.name || m; });
            }
            // Handle models property
            else if (resp.models && Array.isArray(resp.models)) {
              models = resp.models.map(function(m) { return m.id || m.name || m; });
            }
            
            availableModels = models;
            
            // Set first model as default if current model is empty
            if (models.length > 0 && !valueModel) {
              valueModel = models[0];
            }
          } catch (e) {
            modelsError = "Failed to parse models response";
            Logger.e("OpenWebUI", "Models parse error: " + e);
          }
        } else {
          modelsError = "Failed to fetch models (" + xhr.status + ")";
          Logger.e("OpenWebUI", "Models fetch error: " + xhr.status);
        }
      }
    };
    
    xhr.onerror = function() {
      fetchingModels = false;
      modelsError = "Network error";
    };
    
    xhr.send();
  }

  function performLogin() {
      if (!authUrlInput) { ToastService.showError("URL required"); return; }
      if (!authEmailInput || !authPassInput) { ToastService.showError("Email & Password required"); return; }

      loggingIn = true;
      var cleanUrl = authUrlInput.replace(/\/+$/, "");
      var xhr = new XMLHttpRequest();
      xhr.open("POST", cleanUrl + "/api/v1/auths/signin");
      xhr.setRequestHeader("Content-Type", "application/json");
      
      xhr.onreadystatechange = function() {
          if (xhr.readyState === XMLHttpRequest.DONE) {
              loggingIn = false;
              if (xhr.status === 200) {
                  try {
                      var resp = JSON.parse(xhr.responseText);
                      if (resp && resp.token) {
                          if (pluginApi) {
                              pluginApi.pluginSettings.baseUrl = cleanUrl;
                              pluginApi.pluginSettings.apiToken = resp.token;
                              root.valueBaseUrl = cleanUrl;
                              root.valueToken = resp.token;
                              pluginApi.saveSettings();
                              ToastService.showNotice("Logged in successfully");
                              authPassInput = "";
                              authEmailInput = "";
                          }
                      } else {
                          ToastService.showError("Login failed: No token returned");
                      }
                  } catch (e) {
                      ToastService.showError("Login failed: Invalid response");
                  }
              } else {
                  ToastService.showError("Login failed: " + xhr.status + " " + xhr.statusText);
              }
          }
      }
      xhr.onerror = function() {
          loggingIn = false;
          ToastService.showError("Network error. Check URL.");
      }
      xhr.send(JSON.stringify({email: authEmailInput, password: authPassInput}));
  }

  function saveManualKey() {
      if (!authUrlInput) { ToastService.showError("URL required"); return; }
      if (!authKeyInput) { ToastService.showError("API Key required"); return; }
      
      if (pluginApi) {
          var cleanUrl = authUrlInput.replace(/\/+$/, "");
          pluginApi.pluginSettings.baseUrl = cleanUrl;
          pluginApi.pluginSettings.apiToken = authKeyInput.trim();
          root.valueBaseUrl = cleanUrl;
          root.valueToken = authKeyInput.trim();
          pluginApi.saveSettings();
          ToastService.showNotice("API Key saved");
          authKeyInput = "";
      }
  }

  function logout() {
      if (pluginApi) {
          pluginApi.pluginSettings.apiToken = "";
          root.valueToken = "";
          pluginApi.saveSettings();
          ToastService.showNotice("Logged out successfully");
      }
  }

  // Authentication Status Section
  Rectangle {
    Layout.fillWidth: true
    height: authStatusContent.implicitHeight + Style.marginM * 2
    color: isAuthenticated ? Qt.rgba(0, 0.8, 0.2, 0.15) : Qt.rgba(0.8, 0.2, 0, 0.15)
    radius: Style.radiusM
    border.color: isAuthenticated ? Qt.rgba(0, 0.8, 0.2, 0.4) : Qt.rgba(0.8, 0.2, 0, 0.4)
    border.width: 1

    RowLayout {
      id: authStatusContent
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM

      // Status indicator circle
      Rectangle {
        Layout.preferredWidth: 16
        Layout.preferredHeight: 16
        radius: 8
        color: isAuthenticated ? Qt.rgba(0, 0.8, 0.2, 1) : Qt.rgba(0.8, 0.2, 0, 1)
        border.color: isAuthenticated ? Qt.rgba(0, 1, 0.2, 1) : Qt.rgba(1, 0.2, 0, 1)
        border.width: 2

        // Pulse animation for logged in state
        SequentialAnimation on scale {
          running: isAuthenticated
          loops: Animation.Infinite
          NumberAnimation { from: 1.0; to: 1.2; duration: 1000; easing.type: Easing.InOutQuad }
          NumberAnimation { from: 1.2; to: 1.0; duration: 1000; easing.type: Easing.InOutQuad }
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXXS

        NText {
          text: isAuthenticated ? "Authentication Status: Logged In" : "Authentication Status: Not Authenticated"
          font.pointSize: Style.fontSizeM
          font.weight: Font.Bold
          color: isAuthenticated ? Qt.rgba(0, 0.9, 0.2, 1) : Qt.rgba(0.9, 0.2, 0, 1)
        }

        NText {
          text: isAuthenticated 
                  ? "Connected to: " + (valueBaseUrl || "Unknown")
                  : "Please authenticate to your OpenWebUI account"
          font.pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
          wrapMode: Text.Wrap
          Layout.fillWidth: true
        }
      }

      NButton {
        text: "Logout"
        visible: isAuthenticated
        onClicked: logout()
      }
    }
  }

  // Show login form when not authenticated
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    visible: !isAuthenticated

    NIcon {
      icon: "login"
      pointSize: 48
      color: Color.mPrimary
      Layout.alignment: Qt.AlignHCenter
    }

    NText {
      text: "Connect to OpenWebUI"
      font.pointSize: Style.fontSizeXL
      font.weight: Font.Bold
      Layout.alignment: Qt.AlignHCenter
      color: Color.mOnSurface
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginXXS
      
      NText {
        text: "Server URL"
        font.pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }
      
      Rectangle {
        Layout.fillWidth: true
        height: 36
        color: Color.mSurfaceVariant
        radius: Style.radiusS
        border.width: 0
        
        TextInput {
          anchors.fill: parent
          anchors.margins: Style.marginS
          text: authUrlInput
          color: Color.mOnSurface
          font.pointSize: Style.fontSizeS
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          onTextChanged: authUrlInput = text
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginXXS
      
      NText {
        text: "Email"
        font.pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }
      
      Rectangle {
        Layout.fillWidth: true
        height: 36
        color: Color.mSurfaceVariant
        radius: Style.radiusS
        border.width: 0
        
        TextInput {
          anchors.fill: parent
          anchors.margins: Style.marginS
          text: authEmailInput
          color: Color.mOnSurface
          font.pointSize: Style.fontSizeS
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          onTextChanged: authEmailInput = text
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginXXS
      
      NText {
        text: "Password"
        font.pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }
      
      Rectangle {
        Layout.fillWidth: true
        height: 36
        color: Color.mSurfaceVariant
        radius: Style.radiusS
        border.width: 0
        
        TextInput {
          anchors.fill: parent
          anchors.margins: Style.marginS
          text: authPassInput
          echoMode: TextInput.Password
          passwordCharacter: "•"
          color: Color.mOnSurface
          font.pointSize: Style.fontSizeS
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          onTextChanged: authPassInput = text
          onAccepted: performLogin()
        }
      }
    }

    NButton {
      text: loggingIn ? "Logging in..." : "Log In"
      enabled: !loggingIn
      Layout.fillWidth: true
      Layout.topMargin: Style.marginS
      onClicked: performLogin()
    }

    Rectangle {
      Layout.fillWidth: true
      height: 1
      color: Style.capsuleBorderColor
      Layout.margins: Style.marginS
    }

    NText {
      text: "Or enter API Key manually"
      font.pointSize: Style.fontSizeXS
      color: Color.mOnSurfaceVariant
      Layout.alignment: Qt.AlignHCenter
    }

    Rectangle {
      Layout.fillWidth: true
      height: 36
      color: Color.mSurfaceVariant
      radius: Style.radiusS
      border.width: 0
      
      TextInput {
          id: apiKeyInput
          anchors.fill: parent
          anchors.margins: Style.marginS
          text: authKeyInput
          echoMode: TextInput.Password
          passwordCharacter: "•"
          color: Color.mOnSurface
          font.pointSize: Style.fontSizeS
          verticalAlignment: TextInput.AlignVCenter
          clip: true
          onTextChanged: authKeyInput = text
        }
        
        Text {
          anchors.fill: parent
          anchors.margins: Style.marginS
          text: "sk-..."
          color: Color.mOnSurfaceVariant
          font.pointSize: Style.fontSizeS
          verticalAlignment: Text.AlignVCenter
          visible: !apiKeyInput.text && !apiKeyInput.activeFocus
          opacity: 0.7
        }
      }

    NButton {
      text: "Save API Key"
      Layout.fillWidth: true
      Layout.topMargin: Style.marginS
      onClicked: saveManualKey()
    }
  }

  // Show configuration options when authenticated
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    visible: isAuthenticated

    NText {
      text: "Chat Configuration"
      font.pointSize: Style.fontSizeL
      font.weight: Font.Bold
      color: Color.mOnSurface
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXXS

        NLabel {
          label: "Default Model"
          description: "Model to use for chat requests"
        }

        ComboBox {
          id: modelComboSettings
          Layout.fillWidth: true
          enabled: !fetchingModels && availableModels.length > 0
          editable: true
          model: availableModels.length > 0 ? availableModels : [valueModel || "No models available"]
          currentIndex: {
            if (availableModels.length === 0) return 0;
            var idx = availableModels.indexOf(valueModel);
            return idx >= 0 ? idx : 0;
          }
          onAccepted: {
            root.valueModel = editText;
          }
          onActivated: {
            if (availableModels.length > 0) {
              root.valueModel = availableModels[currentIndex];
            }
          }
          
          delegate: ItemDelegate {
            width: modelComboSettings.width
            contentItem: RowLayout {
              spacing: Style.marginS
              
              NIcon {
                icon: "robot"
                pointSize: Style.fontSizeM
                color: Color.mPrimary
              }
              
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXXS
                
                NText {
                  text: modelData
                  font.pointSize: Style.fontSizeS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                  font.weight: Font.Medium
                }
              }
            }
            highlighted: modelComboSettings.highlightedIndex === index
            background: Rectangle {
              color: highlighted ? Color.mHover : "transparent"
              radius: Style.radiusS
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginXXS
          visible: modelsError || fetchingModels

          NIcon {
            icon: modelsError ? "alert-circle" : "loader-2"
            pointSize: Style.fontSizeXS
            color: modelsError ? Color.mOnSurfaceVariant : Color.mPrimary
            
            RotationAnimation on rotation {
              running: fetchingModels
              loops: Animation.Infinite
              from: 0
              to: 360
              duration: 1000
            }
          }

          NText {
            text: modelsError ? modelsError : "Loading models..."
            font.pointSize: Style.fontSizeXS
            color: modelsError ? Color.mOnSurfaceVariant : Color.mOnSurfaceVariant
            Layout.fillWidth: true
          }
        }

        NText {
          text: availableModels.length + " models available"
          font.pointSize: Style.fontSizeXS
          color: Color.mPrimary
          visible: availableModels.length > 0 && !fetchingModels
        }
      }

      NButton {
        text: fetchingModels ? "Refreshing..." : "Refresh"
        enabled: !fetchingModels
        onClicked: fetchModels()
        Layout.alignment: Qt.AlignBottom
      }
    }

    Rectangle {
      Layout.fillWidth: true
      height: 1
      color: Style.capsuleBorderColor
      Layout.topMargin: Style.marginS
      Layout.bottomMargin: Style.marginS
    }

    NText {
      text: "Panel Configuration"
      font.pointSize: Style.fontSizeL
      font.weight: Font.Bold
      color: Color.mOnSurface
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NLabel {
        label: "Panel Position"
        description: "Where the panel should appear on screen"
      }

      ComboBox {
        Layout.fillWidth: true
        model: [
          "Top Left",
          "Top",
          "Top Right",
          "Right",
          "Bottom Right",
          "Bottom",
          "Bottom Left",
          "Left"
        ]
        currentIndex: {
          var pos = root.valuePosition;
          if (pos === "top-left") return 0;
          if (pos === "top") return 1;
          if (pos === "top-right") return 2;
          if (pos === "right") return 3;
          if (pos === "bottom-right") return 4;
          if (pos === "bottom") return 5;
          if (pos === "bottom-left") return 6;
          if (pos === "left") return 7;
          return 3; // default to right
        }
        onActivated: {
          var positions = ["top-left", "top", "top-right", "right", "bottom-right", "bottom", "bottom-left", "left"];
          root.valuePosition = positions[currentIndex];
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NLabel {
        label: "Panel width"
        description: "Adjust panel width in pixels"
      }

      Slider {
        from: 320
        to: 1280
        stepSize: 10
        value: root.valueWidth
        onValueChanged: root.valueWidth = value
      }

      NText {
        text: root.valueWidth.toFixed(0) + " px"
        font.pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NLabel {
        label: "Panel height"
        description: "Adjust panel height in pixels"
      }

      Slider {
        from: 320
        to: 1080
        stepSize: 10
        value: root.valueHeight
        onValueChanged: root.valueHeight = value
      }

      NText {
        text: root.valueHeight.toFixed(0) + " px"
        font.pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NLabel {
        label: "Remember Chat History"
        description: "Persist chat messages between sessions"
        Layout.fillWidth: true
      }

      CheckBox {
        checked: root.valueRememberHistory
        onToggled: root.valueRememberHistory = checked
      }
    }

    NText {
      text: "Your token is stored locally in plugin settings."
      font.pointSize: Style.fontSizeXS
      color: Color.mOnSurfaceVariant
      wrapMode: Text.Wrap
      Layout.fillWidth: true
      Layout.topMargin: Style.marginM
    }
  }

  function saveSettings() {
    if (!pluginApi) {
      Logger.e("OpenWebUI", "Cannot save settings: pluginApi missing");
      return;
    }

    pluginApi.pluginSettings.baseUrl = root.valueBaseUrl.trim();
    pluginApi.pluginSettings.apiToken = root.valueToken.trim();
    pluginApi.pluginSettings.defaultModel = root.valueModel.trim();
    pluginApi.pluginSettings.panelPosition = root.valuePosition;
    pluginApi.pluginSettings.panelWidth = root.valueWidth;
    pluginApi.pluginSettings.panelHeight = root.valueHeight;
    pluginApi.pluginSettings.rememberHistory = root.valueRememberHistory;

    pluginApi.saveSettings();
    Logger.i("OpenWebUI", "Settings saved");
  }
}
