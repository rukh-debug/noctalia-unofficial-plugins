import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets
import qs.Services.UI

ColumnLayout {
  id: root
  property var pluginApi: null

  property string valueBaseUrl: pluginApi?.pluginSettings?.baseUrl || pluginApi?.manifest?.metadata?.defaultSettings?.baseUrl || ""
  property string valueToken: pluginApi?.pluginSettings?.apiToken || pluginApi?.manifest?.metadata?.defaultSettings?.apiToken || ""
  property string valueModel: pluginApi?.pluginSettings?.defaultModel || pluginApi?.manifest?.metadata?.defaultSettings?.defaultModel || ""
  property string valuePosition: pluginApi?.pluginSettings?.panelPosition || pluginApi?.manifest?.metadata?.defaultSettings?.panelPosition || "bottom"
  property double valueWidth: pluginApi?.pluginSettings?.panelWidth || pluginApi?.manifest?.metadata?.defaultSettings?.panelWidth || 640
  property double valueHeight: pluginApi?.pluginSettings?.panelHeight || pluginApi?.manifest?.metadata?.defaultSettings?.panelHeight || 560
  property bool valueRememberHistory: pluginApi?.pluginSettings?.rememberHistory ?? pluginApi?.manifest?.metadata?.defaultSettings?.rememberHistory ?? true
  property bool valueReopenOnSameMonitor: pluginApi?.pluginSettings?.openAfterResponse ?? pluginApi?.manifest?.metadata?.defaultSettings?.openAfterResponse ?? true

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

  spacing: Style.marginL

  Component.onCompleted: {
    Logger.i("OpenWebUI", "Settings UI loaded");
    if (isAuthenticated) {
      fetchModels();
    }
  }

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
            
            if (resp.data && Array.isArray(resp.data)) {
              models = resp.data.map(function(m) { return m.id || m.name || m; });
            } 
            else if (Array.isArray(resp)) {
              models = resp.map(function(m) { return m.id || m.name || m; });
            }
            else if (resp.models && Array.isArray(resp.models)) {
              models = resp.models.map(function(m) { return m.id || m.name || m; });
            }
            
            availableModels = models;
            
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

  // ─── Reusable: Section Card ───
  component SettingsCard: Rectangle {
    id: card
    default property alias cardContent: cardColumn.data
    property string title: ""

    Layout.fillWidth: true
    implicitHeight: cardInnerCol.implicitHeight + Style.marginM * 2
    color: Qt.alpha(Color.mSurfaceVariant, 0.35)
    radius: Style.radiusM
    border.width: 1
    border.color: Qt.alpha(Style.capsuleBorderColor, 0.5)

    ColumnLayout {
      id: cardInnerCol
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM

      NText {
        text: card.title
        font.pointSize: Style.fontSizeM
        font.weight: Font.DemiBold
        color: Color.mOnSurface
        visible: card.title !== ""
      }

      ColumnLayout {
        id: cardColumn
        Layout.fillWidth: true
        spacing: Style.marginS
      }
    }
  }

  // ─── Reusable: Styled Text Field ───
  component StyledField: Rectangle {
    id: fieldRoot
    property alias text: fieldInput.text
    property alias echoMode: fieldInput.echoMode
    property alias passwordCharacter: fieldInput.passwordCharacter
    property string placeholder: ""
    signal accepted()
    signal textEdited(string newText)

    Layout.fillWidth: true
    height: 40
    color: Color.mSurfaceVariant
    radius: Style.radiusS
    border.width: fieldInput.activeFocus ? 2 : 1
    border.color: fieldInput.activeFocus ? Color.mPrimary : Qt.alpha(Style.capsuleBorderColor, 0.5)

    Behavior on border.color { ColorAnimation { duration: 150 } }

    TextInput {
      id: fieldInput
      anchors.fill: parent
      anchors.leftMargin: Style.marginS + 2
      anchors.rightMargin: Style.marginS + 2
      anchors.topMargin: Style.marginXS
      anchors.bottomMargin: Style.marginXS
      color: Color.mOnSurface
      font.pointSize: Style.fontSizeS
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      onTextChanged: fieldRoot.textEdited(text)
      onAccepted: fieldRoot.accepted()
    }

    Text {
      anchors.fill: fieldInput
      text: fieldRoot.placeholder
      color: Qt.alpha(Color.mOnSurfaceVariant, 0.5)
      font.pointSize: Style.fontSizeS
      verticalAlignment: Text.AlignVCenter
      visible: !fieldInput.text && !fieldInput.activeFocus
    }
  }

  // ─── Reusable: Setting Row (label + control) ───
  component SettingRow: RowLayout {
    property string label: ""
    property string description: ""
    default property alias control: controlSlot.data

    Layout.fillWidth: true
    spacing: Style.marginM

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 2

      NText {
        text: parent.parent.label
        font.pointSize: Style.fontSizeS
        font.weight: Font.Medium
        color: Color.mOnSurface
      }

      NText {
        text: parent.parent.description
        font.pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        visible: parent.parent.description !== ""
        wrapMode: Text.Wrap
        Layout.fillWidth: true
      }
    }

    Item {
      id: controlSlot
      Layout.alignment: Qt.AlignVCenter
      implicitWidth: childrenRect.width
      implicitHeight: childrenRect.height
    }
  }

  // ─── Reusable: Styled ComboBox ───
  component StyledComboBox: ComboBox {
    id: styledCombo
    Layout.fillWidth: true
    implicitHeight: 40

    background: Rectangle {
      color: Color.mSurfaceVariant
      radius: Style.radiusS
      border.width: styledCombo.activeFocus || styledCombo.popup.visible ? 2 : 1
      border.color: styledCombo.activeFocus || styledCombo.popup.visible ? Color.mPrimary : Qt.alpha(Style.capsuleBorderColor, 0.5)

      Behavior on border.color { ColorAnimation { duration: 150 } }
    }

    contentItem: NText {
      leftPadding: Style.marginS + 2
      rightPadding: styledCombo.indicator.width + Style.marginS
      text: styledCombo.displayText
      font.pointSize: Style.fontSizeS
      color: Color.mOnSurface
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }

    indicator: NIcon {
      x: styledCombo.width - width - Style.marginS
      y: (styledCombo.height - height) / 2
      icon: "chevron-down"
      pointSize: Style.fontSizeXS
      color: Color.mOnSurfaceVariant

      Behavior on rotation { NumberAnimation { duration: 200 } }
      rotation: styledCombo.popup.visible ? 180 : 0
    }

    popup: Popup {
      y: styledCombo.height + 4
      width: styledCombo.width
      implicitHeight: Math.min(popupListView.contentHeight + 8, 300)
      padding: 4

      background: Rectangle {
        // Use surfaceVariant with full opacity so it's never transparent
        color: Qt.lighter(Color.mSurfaceVariant, 1.1)
        radius: Style.radiusS
        border.width: 1
        border.color: Qt.alpha(Style.capsuleBorderColor, 0.8)

        // Subtle shadow via a darker rect behind
        Rectangle {
          anchors.fill: parent
          anchors.margins: -1
          z: -1
          radius: parent.radius + 1
          color: Qt.alpha("#000000", 0.25)
        }
      }

      contentItem: ListView {
        id: popupListView
        clip: true
        implicitHeight: contentHeight
        model: styledCombo.popup.visible ? styledCombo.delegateModel : null
        currentIndex: styledCombo.highlightedIndex
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
          policy: popupListView.contentHeight > 292 ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
          width: 6

          contentItem: Rectangle {
            implicitWidth: 4
            radius: 2
            color: Qt.alpha(Color.mOnSurfaceVariant, 0.4)
          }
        }
      }
    }

    delegate: ItemDelegate {
      width: styledCombo.width - 8
      height: 36
      highlighted: styledCombo.highlightedIndex === index

      contentItem: NText {
        text: modelData
        font.pointSize: Style.fontSizeS
        color: highlighted ? Color.mPrimary : Color.mOnSurface
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        leftPadding: Style.marginS
      }

      background: Rectangle {
        color: highlighted ? Qt.alpha(Color.mPrimary, 0.1) : (hovered ? Qt.alpha(Color.mOnSurface, 0.05) : "transparent")
        radius: Style.radiusXS

        Behavior on color { ColorAnimation { duration: 100 } }
      }
    }
  }


  // ═══════════════════════════════════════════
  //  Authentication Status
  // ═══════════════════════════════════════════

  Rectangle {
    Layout.fillWidth: true
    implicitHeight: authStatusRow.implicitHeight + Style.marginM * 2
    color: isAuthenticated ? Qt.rgba(0, 0.8, 0.2, 0.08) : Qt.rgba(0.8, 0.2, 0, 0.08)
    radius: Style.radiusM
    border.color: isAuthenticated ? Qt.rgba(0, 0.8, 0.2, 0.25) : Qt.rgba(0.8, 0.2, 0, 0.25)
    border.width: 1

    RowLayout {
      id: authStatusRow
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginS

      Rectangle {
        Layout.preferredWidth: 10
        Layout.preferredHeight: 10
        radius: 5
        color: isAuthenticated ? Qt.rgba(0.2, 0.85, 0.4, 1) : Qt.rgba(0.85, 0.25, 0.1, 1)

        SequentialAnimation on opacity {
          running: isAuthenticated
          loops: Animation.Infinite
          NumberAnimation { from: 1.0; to: 0.4; duration: 1200; easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.4; to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        NText {
          text: isAuthenticated ? "Connected" : "Not Connected"
          font.pointSize: Style.fontSizeS
          font.weight: Font.DemiBold
          color: isAuthenticated ? Qt.rgba(0.2, 0.85, 0.4, 1) : Qt.rgba(0.85, 0.25, 0.1, 1)
        }

        NText {
          text: isAuthenticated 
                  ? valueBaseUrl || "Unknown server"
                  : "Authenticate to get started"
          font.pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
          elide: Text.ElideMiddle
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

  // ═══════════════════════════════════════════
  //  Login Form (when not authenticated)
  // ═══════════════════════════════════════════

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    visible: !isAuthenticated

    NIcon {
      icon: "login"
      pointSize: 40
      color: Color.mPrimary
      Layout.alignment: Qt.AlignHCenter
    }

    NText {
      text: "Connect to OpenWebUI"
      font.pointSize: Style.fontSizeL
      font.weight: Font.Bold
      Layout.alignment: Qt.AlignHCenter
      color: Color.mOnSurface
    }

    SettingsCard {
      title: "Sign In"

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXXS

        NText {
          text: "Server URL"
          font.pointSize: Style.fontSizeXS
          font.weight: Font.Medium
          color: Color.mOnSurfaceVariant
        }

        StyledField {
          text: authUrlInput
          placeholder: "http://localhost:3000"
          onTextEdited: (t) => authUrlInput = t
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXXS

        NText {
          text: "Email"
          font.pointSize: Style.fontSizeXS
          font.weight: Font.Medium
          color: Color.mOnSurfaceVariant
        }

        StyledField {
          text: authEmailInput
          placeholder: "user@example.com"
          onTextEdited: (t) => authEmailInput = t
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXXS

        NText {
          text: "Password"
          font.pointSize: Style.fontSizeXS
          font.weight: Font.Medium
          color: Color.mOnSurfaceVariant
        }

        StyledField {
          text: authPassInput
          echoMode: TextInput.Password
          passwordCharacter: "•"
          placeholder: "••••••••"
          onTextEdited: (t) => authPassInput = t
          onAccepted: performLogin()
        }
      }

      NButton {
        text: loggingIn ? "Logging in..." : "Log In"
        enabled: !loggingIn
        Layout.fillWidth: true
        Layout.topMargin: Style.marginXS
        onClicked: performLogin()
      }
    }

    // Divider
    RowLayout {
      Layout.fillWidth: true
      Layout.topMargin: Style.marginXS
      Layout.bottomMargin: Style.marginXS
      spacing: Style.marginS

      Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(Style.capsuleBorderColor, 0.5) }
      NText {
        text: "or"
        font.pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
      }
      Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(Style.capsuleBorderColor, 0.5) }
    }

    SettingsCard {
      title: "API Key"

      StyledField {
        id: apiKeyFieldInCard
        text: authKeyInput
        echoMode: TextInput.Password
        passwordCharacter: "•"
        placeholder: "sk-..."
        onTextEdited: (t) => authKeyInput = t
      }

      NButton {
        text: "Save API Key"
        Layout.fillWidth: true
        Layout.topMargin: Style.marginXS
        onClicked: saveManualKey()
      }
    }
  }

  // ═══════════════════════════════════════════
  //  Configuration (when authenticated)
  // ═══════════════════════════════════════════

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    visible: isAuthenticated

    // ── Model Selection ──
    SettingsCard {
      title: "Model"

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        StyledComboBox {
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
            width: modelComboSettings.width - 8
            height: 38
            highlighted: modelComboSettings.highlightedIndex === index

            contentItem: RowLayout {
              spacing: Style.marginS
              
              NIcon {
                icon: "bot"
                pointSize: Style.fontSizeXS
                color: highlighted ? Color.mPrimary : Color.mOnSurfaceVariant
              }
              
              NText {
                text: modelData
                font.pointSize: Style.fontSizeS
                color: highlighted ? Color.mPrimary : Color.mOnSurface
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
            }

            background: Rectangle {
              color: highlighted ? Qt.alpha(Color.mPrimary, 0.1) : (hovered ? Qt.alpha(Color.mOnSurface, 0.05) : "transparent")
              radius: Style.radiusXS
              Behavior on color { ColorAnimation { duration: 100 } }
            }
          }
        }

        NButton {
          text: fetchingModels ? "..." : "↻"
          enabled: !fetchingModels
          onClicked: fetchModels()

          ToolTip.text: "Refresh models"
          ToolTip.visible: hovered
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS
        visible: modelsError || fetchingModels || (availableModels.length > 0 && !fetchingModels)

        NIcon {
          icon: modelsError ? "alert-circle" : (fetchingModels ? "loader-2" : "check-circle")
          pointSize: Style.fontSizeXS
          color: modelsError ? Qt.alpha(Color.mError, 0.7) : (fetchingModels ? Color.mPrimary : Qt.alpha(Color.mOnSurfaceVariant, 0.6))
          
          RotationAnimation on rotation {
            running: fetchingModels
            loops: Animation.Infinite
            from: 0; to: 360; duration: 1000
          }
        }

        NText {
          text: modelsError ? modelsError : (fetchingModels ? "Loading models..." : availableModels.length + " models available")
          font.pointSize: Style.fontSizeXS
          color: modelsError ? Qt.alpha(Color.mError, 0.7) : Color.mOnSurfaceVariant
          Layout.fillWidth: true
        }
      }
    }

    // ── Panel Position ──
    SettingsCard {
      title: "Panel Layout"

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS

        NText {
          text: "Position"
          font.pointSize: Style.fontSizeXS
          font.weight: Font.Medium
          color: Color.mOnSurfaceVariant
        }

        StyledComboBox {
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
            return 3;
          }
          onActivated: {
            var positions = ["top-left", "top", "top-right", "right", "bottom-right", "bottom", "bottom-left", "left"];
            root.valuePosition = positions[currentIndex];
          }
        }
      }

      // Width slider
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS
        Layout.topMargin: Style.marginXS

        RowLayout {
          Layout.fillWidth: true

          NText {
            text: "Width"
            font.pointSize: Style.fontSizeXS
            font.weight: Font.Medium
            color: Color.mOnSurfaceVariant
            Layout.fillWidth: true
          }

          NText {
            text: root.valueWidth.toFixed(0) + " px"
            font.pointSize: Style.fontSizeXS
            font.weight: Font.Medium
            color: Color.mPrimary
          }
        }

        Slider {
          Layout.fillWidth: true
          from: 320
          to: 1280
          stepSize: 10
          value: root.valueWidth
          onValueChanged: root.valueWidth = value
        }
      }

      // Height slider
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS

        RowLayout {
          Layout.fillWidth: true

          NText {
            text: "Height"
            font.pointSize: Style.fontSizeXS
            font.weight: Font.Medium
            color: Color.mOnSurfaceVariant
            Layout.fillWidth: true
          }

          NText {
            text: root.valueHeight.toFixed(0) + " px"
            font.pointSize: Style.fontSizeXS
            font.weight: Font.Medium
            color: Color.mPrimary
          }
        }

        Slider {
          Layout.fillWidth: true
          from: 320
          to: 1080
          stepSize: 10
          value: root.valueHeight
          onValueChanged: root.valueHeight = value
        }
      }
    }

    // ── Behavior ──
    SettingsCard {
      title: "Behavior"

      SettingRow {
        label: "Remember Chat History"
        description: "Persist messages between sessions"

        CheckBox {
          checked: root.valueRememberHistory
          onToggled: root.valueRememberHistory = checked
        }
      }

      Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Qt.alpha(Style.capsuleBorderColor, 0.3)
      }

      SettingRow {
        label: "Open Panel After Response"
        description: "Show panel on active monitor when generation finishes"

        CheckBox {
          checked: root.valueReopenOnSameMonitor
          onToggled: root.valueReopenOnSameMonitor = checked
        }
      }
    }

    // Footer note
    NText {
      text: "Auth token stored locally in plugin settings."
      font.pointSize: Style.fontSizeXS
      color: Qt.alpha(Color.mOnSurfaceVariant, 0.6)
      Layout.alignment: Qt.AlignHCenter
      Layout.topMargin: Style.marginS
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
    pluginApi.pluginSettings.openAfterResponse = root.valueReopenOnSameMonitor;

    pluginApi.saveSettings();
    Logger.i("OpenWebUI", "Settings saved");
  }
}
