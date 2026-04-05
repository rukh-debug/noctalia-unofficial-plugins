import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets
import qs.Services.UI

ColumnLayout {
  id: root

  property var pluginApi: null

  property string valueClientId: pluginApi?.pluginSettings?.auth?.clientId ?? pluginApi?.manifest?.metadata?.defaultSettings?.auth?.clientId ?? ""
  property string valueClientSecret: pluginApi?.pluginSettings?.auth?.clientSecret ?? pluginApi?.manifest?.metadata?.defaultSettings?.auth?.clientSecret ?? ""
  property string valueIdentity: pluginApi?.pluginSettings?.auth?.identity
      ?? pluginApi?.pluginSettings?.auth?.username
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.auth?.identity
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.auth?.username
      ?? ""
  property bool valueRememberSession: pluginApi?.pluginSettings?.auth?.rememberSession ?? pluginApi?.manifest?.metadata?.defaultSettings?.auth?.rememberSession ?? true
  property string loginPasswordInput: ""

  property string valuePanelPosition: normalizePanelPosition(
      pluginApi?.pluginSettings?.panelPosition
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelPosition
      ?? "right")
  property int valuePanelWidthMin: Math.max(560,
      Number(pluginApi?.pluginSettings?.panelWidthMin
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelWidthMin
      ?? 760))
  property int valuePanelWidthMax: Math.max(valuePanelWidthMin,
      Number(pluginApi?.pluginSettings?.panelWidthMax
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelWidthMax
      ?? 1800))
  property int valuePanelWidth: Number(pluginApi?.pluginSettings?.panelWidth
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelWidth
      ?? 1120)
  property int valuePanelHeight: Number(pluginApi?.pluginSettings?.panelHeight
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelHeight
      ?? 760)

  property bool valueMinimalControls: pluginApi?.pluginSettings?.reader?.minimalControls
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.reader?.minimalControls
      ?? true
  property bool valueUtilityCollapsed: pluginApi?.pluginSettings?.reader?.utilityCollapsed
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.reader?.utilityCollapsed
      ?? false

  property string valueQuality: pluginApi?.pluginSettings?.reader?.quality ?? pluginApi?.manifest?.metadata?.defaultSettings?.reader?.quality ?? "data-saver"
  property string valuePreferredLanguage: pluginApi?.pluginSettings?.reader?.preferredLanguage ?? pluginApi?.manifest?.metadata?.defaultSettings?.reader?.preferredLanguage ?? "en"
  property string valueTranslatedLanguagesCsv: (
      pluginApi?.pluginSettings?.reader?.translatedLanguages
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.reader?.translatedLanguages
      ?? ["en"]).join(",")

  property bool ratingSafe: hasRating("safe")
  property bool ratingSuggestive: hasRating("suggestive")
  property bool ratingErotica: hasRating("erotica")
  property bool ratingPornographic: hasRating("pornographic")

  property int valueSearchPageSize: Number(pluginApi?.pluginSettings?.network?.searchPageSize
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.network?.searchPageSize
      ?? 20)
  property int valueCooldownSeconds: Number(pluginApi?.pluginSettings?.network?.cooldownSecondsOn429
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.network?.cooldownSecondsOn429
      ?? 8)
    property int valueRequestPacingMs: Number(pluginApi?.pluginSettings?.network?.requestPacingMs
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.network?.requestPacingMs
      ?? 250)
    property int valueMaxRetryAttempts: Number(pluginApi?.pluginSettings?.network?.maxRetryAttempts
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.network?.maxRetryAttempts
      ?? 2)
    property int valueRetryBaseDelayMs: Number(pluginApi?.pluginSettings?.network?.retryBaseDelayMs
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.network?.retryBaseDelayMs
      ?? 400)

    property string valueLoggingMode: normalizeDiagnosticsMode(
      pluginApi?.pluginSettings?.diagnostics?.loggingMode
      ?? pluginApi?.manifest?.metadata?.defaultSettings?.diagnostics?.loggingMode
      ?? "normal")

  readonly property bool widthIsValid: valuePanelWidth >= valuePanelWidthMin && valuePanelWidth <= valuePanelWidthMax

  spacing: Style.marginM

  function normalizePanelPosition(positionValue) {
    var normalized = String(positionValue || "").toLowerCase().trim();
    return normalized === "left" ? "left" : "right";
  }

  function normalizeDiagnosticsMode(modeValue) {
    var normalized = String(modeValue || "").toLowerCase().trim();
    if (normalized === "off" || normalized === "verbose") {
      return normalized;
    }
    return "normal";
  }

  function normalizeWidth(widthValue) {
    var numeric = Number(widthValue);
    if (isNaN(numeric)) {
      numeric = valuePanelWidthMin;
    }
    return Math.max(valuePanelWidthMin, Math.min(valuePanelWidthMax, Math.round(numeric)));
  }

  function hasRating(name) {
    var list = pluginApi?.pluginSettings?.reader?.contentRatings
            ?? pluginApi?.manifest?.metadata?.defaultSettings?.reader?.contentRatings
            ?? ["safe", "suggestive", "erotica"];
    for (var i = 0; i < list.length; i++) {
      if (list[i] === name) {
        return true;
      }
    }
    return false;
  }

  function csvToList(csvValue) {
    var parts = String(csvValue || "").split(",");
    var out = [];
    for (var i = 0; i < parts.length; i++) {
      var trimmed = parts[i].trim();
      if (trimmed !== "") {
        out.push(trimmed);
      }
    }
    return out.length > 0 ? out : ["en"];
  }

  function selectedContentRatings() {
    var out = [];
    if (ratingSafe) { out.push("safe"); }
    if (ratingSuggestive) { out.push("suggestive"); }
    if (ratingErotica) { out.push("erotica"); }
    if (ratingPornographic) { out.push("pornographic"); }
    if (out.length === 0) { out.push("safe"); }
    return out;
  }

  function ensureSettingsContainers() {
    if (!pluginApi || !pluginApi.pluginSettings) { return; }
    if (!pluginApi.pluginSettings.auth) { pluginApi.pluginSettings.auth = {}; }
    if (!pluginApi.pluginSettings.reader) { pluginApi.pluginSettings.reader = {}; }
    if (!pluginApi.pluginSettings.network) { pluginApi.pluginSettings.network = {}; }
    if (!pluginApi.pluginSettings.diagnostics) { pluginApi.pluginSettings.diagnostics = {}; }
  }

  function applyAuthSettingsOnly() {
    ensureSettingsContainers();
    pluginApi.pluginSettings.auth.clientId = valueClientId.trim();
    pluginApi.pluginSettings.auth.clientSecret = valueClientSecret.trim();
    pluginApi.pluginSettings.auth.identity = valueIdentity.trim();
    pluginApi.pluginSettings.auth.username = valueIdentity.trim();
    pluginApi.pluginSettings.auth.rememberSession = valueRememberSession;
  }

  function persistLayoutSettings() {
    ensureSettingsContainers();
    pluginApi.pluginSettings.panelDetached = true;
    pluginApi.pluginSettings.panelPosition = normalizePanelPosition(valuePanelPosition);
    pluginApi.pluginSettings.panelWidthMin = valuePanelWidthMin;
    pluginApi.pluginSettings.panelWidthMax = valuePanelWidthMax;
    pluginApi.pluginSettings.panelWidth = normalizeWidth(valuePanelWidth);
    pluginApi.pluginSettings.panelHeight = Math.max(480, Number(valuePanelHeight));
    pluginApi.pluginSettings.reader.minimalControls = valueMinimalControls;
    pluginApi.pluginSettings.reader.utilityCollapsed = valueUtilityCollapsed;
  }

  function triggerSettingsLogin(passwordValue) {
    if (!pluginApi || !pluginApi.mainInstance) { return; }
    applyAuthSettingsOnly();
    persistLayoutSettings();
    pluginApi.saveSettings();
    pluginApi.mainInstance.requestLogin(passwordValue || "");
  }

  function applyLayoutNow() {
    if (!pluginApi) { return; }
    persistLayoutSettings();
    pluginApi.saveSettings();
    if (pluginApi.mainInstance) {
      pluginApi.mainInstance.applyReaderLayoutPreferences(
          valuePanelPosition,
          normalizeWidth(valuePanelWidth),
          valueMinimalControls,
          valueUtilityCollapsed,
          true);
    }
    ToastService.showNotice("Reader layout applied");
  }

  function saveSettings(showNotice) {
    if (!pluginApi) { return; }
    ensureSettingsContainers();
    applyAuthSettingsOnly();
    persistLayoutSettings();

    if (!valueRememberSession) {
      pluginApi.pluginSettings.auth.refreshToken = "";
      if (pluginApi.mainInstance) {
        pluginApi.mainInstance.clearSession(false);
      }
    }

    pluginApi.pluginSettings.reader.quality = valueQuality;
    pluginApi.pluginSettings.reader.preferredLanguage = valuePreferredLanguage.trim() || "en";
    pluginApi.pluginSettings.reader.translatedLanguages = csvToList(valueTranslatedLanguagesCsv);
    pluginApi.pluginSettings.reader.contentRatings = selectedContentRatings();
    pluginApi.pluginSettings.network.searchPageSize = Math.max(1, Math.min(100, valueSearchPageSize));
    pluginApi.pluginSettings.network.cooldownSecondsOn429 = Math.max(1, valueCooldownSeconds);
    pluginApi.pluginSettings.network.requestPacingMs = Math.max(0, Math.min(3000, valueRequestPacingMs));
    pluginApi.pluginSettings.network.maxRetryAttempts = Math.max(0, Math.min(5, valueMaxRetryAttempts));
    pluginApi.pluginSettings.network.retryBaseDelayMs = Math.max(100, Math.min(10000, valueRetryBaseDelayMs));
    pluginApi.pluginSettings.diagnostics.loggingMode = normalizeDiagnosticsMode(valueLoggingMode);
    pluginApi.saveSettings();

    if (pluginApi.mainInstance && pluginApi.mainInstance.applyDiagnosticsMode) {
      pluginApi.mainInstance.applyDiagnosticsMode(pluginApi.pluginSettings.diagnostics.loggingMode);
    }

    if (showNotice) {
      ToastService.showNotice("MangaDex settings saved");
    }
  }

  // ===== Inline Components =====

  component SettingsCard: Rectangle {
    id: card
    property string title: ""
    property string icon: "settings"
    property string subtitle: ""
    default property alias cardContent: cardContentColumn.data

    Layout.fillWidth: true
    implicitHeight: cardColumn.implicitHeight + Style.marginM * 2
    radius: Style.radiusM
    color: Qt.alpha(Color.mSurfaceVariant, 0.34)
    border.width: 1
    border.color: Qt.alpha(Style.capsuleBorderColor, 0.55)

    ColumnLayout {
      id: cardColumn
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginS

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NIcon {
          icon: card.icon
          pointSize: Style.fontSizeM
          color: Color.mPrimary
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2

          NText {
            text: card.title
            pointSize: Style.fontSizeM
            font.weight: Font.DemiBold
            color: Color.mOnSurface
          }

          NText {
            Layout.fillWidth: true
            visible: card.subtitle !== ""
            text: card.subtitle
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
            wrapMode: Text.Wrap
          }
        }
      }

      ColumnLayout {
        id: cardContentColumn
        Layout.fillWidth: true
        spacing: Style.marginS
      }
    }
  }

  component StyledField: TextField {
    id: styledField

    property color borderColor: Qt.alpha(Style.capsuleBorderColor, 0.65)

    Layout.fillWidth: true
    color: Color.mOnSurface
    font.pointSize: Style.fontSizeS
    padding: Style.marginS
    leftPadding: Style.marginM
    rightPadding: Style.marginM
    placeholderTextColor: Qt.alpha(Color.mOnSurfaceVariant, 0.75)
    selectByMouse: true

    background: Rectangle {
      radius: Style.radiusS
      color: Qt.alpha(Color.mSurface, 0.55)
      border.width: styledField.activeFocus ? 2 : 1
      border.color: styledField.activeFocus ? Qt.alpha(Color.mPrimary, 0.9) : styledField.borderColor

      Behavior on border.color {
        ColorAnimation { duration: 150 }
      }
    }
  }

  component StyledComboBox: ComboBox {
    id: styledCombo

    property bool popupOpen: styledCombo.popup.visible

    Layout.fillWidth: true
    implicitHeight: 40

    background: Rectangle {
      radius: Style.radiusS
      color: Qt.alpha(Color.mSurface, 0.55)
      border.width: styledCombo.activeFocus || styledCombo.popup.visible ? 2 : 1
      border.color: styledCombo.activeFocus || styledCombo.popup.visible
          ? Qt.alpha(Color.mPrimary, 0.9)
          : Qt.alpha(Style.capsuleBorderColor, 0.65)

      Behavior on border.color {
        ColorAnimation { duration: 150 }
      }
    }

    contentItem: NText {
      leftPadding: Style.marginM
      rightPadding: styledCombo.indicator.width + Style.marginM
      text: styledCombo.displayText
      pointSize: Style.fontSizeS
      color: Color.mOnSurface
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }

    indicator: NIcon {
      x: styledCombo.width - width - Style.marginM
      y: (styledCombo.height - height) / 2
      icon: "chevron-down"
      pointSize: Style.fontSizeXS
      color: Color.mOnSurfaceVariant
      rotation: styledCombo.popupOpen ? 180 : 0

      Behavior on rotation {
        NumberAnimation { duration: 200 }
      }
    }

    popup: Popup {
      y: styledCombo.height + 4
      width: styledCombo.width
      implicitHeight: contentColumn.implicitHeight + Style.marginS * 2
      padding: Style.marginS

      background: Rectangle {
        radius: Style.radiusS
        color: Color.mSurface
        border.width: 1
        border.color: Qt.alpha(Style.capsuleBorderColor, 0.65)

        layer.enabled: true
        layer.effect: Item {
          Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            z: -1
            radius: Style.radiusS + 2
            color: "transparent"
            border.width: 8
            border.color: Qt.rgba(0, 0, 0, 0.15)
          }
        }
      }

      contentItem: ColumnLayout {
        id: contentColumn
        spacing: 2

        Repeater {
          model: styledCombo.model

          Rectangle {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            implicitHeight: 32
            radius: Style.radiusS
            color: index === styledCombo.currentIndex ? Qt.alpha(Color.mPrimary, 0.15) : "transparent"

            NText {
              anchors.left: parent.left
              anchors.leftMargin: Style.marginM
              anchors.verticalCenter: parent.verticalCenter
              text: modelData
              pointSize: Style.fontSizeS
              color: index === styledCombo.currentIndex ? Color.mPrimary : Color.mOnSurface
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: parent.color = Qt.alpha(Color.mPrimary, 0.1)
              onExited: parent.color = index === styledCombo.currentIndex ? Qt.alpha(Color.mPrimary, 0.15) : "transparent"
              onClicked: {
                styledCombo.currentIndex = index;
                styledCombo.activated(index);
                styledCombo.popup.close();
              }
            }
          }
        }
      }
    }
  }

  component SectionLabel: NText {
    pointSize: Style.fontSizeXS
    font.weight: Font.Medium
    color: Color.mOnSurfaceVariant
  }

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
        text: label
        pointSize: Style.fontSizeS
        color: Color.mOnSurface
      }

      NText {
        Layout.fillWidth: true
        text: description
        pointSize: Style.fontSizeXS
        color: Color.mOnSurfaceVariant
        visible: description !== ""
        wrapMode: Text.Wrap
      }
    }

    Row {
      id: controlSlot
      spacing: Style.marginS
    }
  }

  component ErrorBanner: Rectangle {
    property string message: ""

    visible: message !== ""
    Layout.fillWidth: true
    implicitHeight: errorRow.implicitHeight + Style.marginS * 2
    radius: Style.radiusS
    color: Qt.rgba(0.937, 0.267, 0.267, 0.12)
    border.width: 1
    border.color: Qt.rgba(0.937, 0.267, 0.267, 0.25)

    RowLayout {
      id: errorRow
      anchors.fill: parent
      anchors.margins: Style.marginS
      spacing: Style.marginS

      NIcon {
        icon: "alert-triangle"
        pointSize: Style.fontSizeS
        color: "#ef4444"
      }

      NText {
        Layout.fillWidth: true
        text: message
        color: "#ef4444"
        wrapMode: Text.Wrap
        pointSize: Style.fontSizeXS
      }
    }
  }

  component StatusDot: Rectangle {
    property bool active: false
    property bool error: false

    width: 10
    height: 10
    radius: 5
    color: error ? "#ef4444" : (active ? "#22c55e" : Color.mOnSurfaceVariant)

    SequentialAnimation on opacity {
      running: parent.visible
      loops: Animation.Infinite
      NumberAnimation { to: 0.4; duration: 1200; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
    }
  }

  // ===== Header =====

  NText {
    text: "MangaDex Reader"
    pointSize: Style.fontSizeL
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NText {
    Layout.fillWidth: true
    text: "Configure authentication, reader preferences, and panel behavior. Password is never saved."
    wrapMode: Text.Wrap
    color: Color.mOnSurfaceVariant
    pointSize: Style.fontSizeS
  }

  // ===== Tab Bar =====

  NTabBar {
    id: tabBar
    Layout.fillWidth: true
    Layout.bottomMargin: Style.marginM
    currentIndex: tabView.currentIndex
    distributeEvenly: true

    NTabButton {
      text: "Account"
      tabIndex: 0
      checked: tabBar.currentIndex === 0
    }

    NTabButton {
      text: "Reader"
      tabIndex: 1
      checked: tabBar.currentIndex === 1
    }

    NTabButton {
      text: "Advanced"
      tabIndex: 2
      checked: tabBar.currentIndex === 2
    }
  }

  // ===== Tab Content =====

  NTabView {
    id: tabView
    Layout.fillWidth: true
    Layout.fillHeight: true
    currentIndex: tabBar.currentIndex

    // ===== Account Tab =====
    ColumnLayout {
      spacing: Style.marginM

      // Auth Status Card
      Rectangle {
        Layout.fillWidth: true
        implicitHeight: statusRow.implicitHeight + Style.marginM * 2
        radius: Style.radiusM
        color: {
          if (pluginApi?.mainInstance?.isAuthenticated) {
            return Qt.rgba(0, 0.8, 0.2, 0.08);
          }
          if ((pluginApi?.mainInstance?.authError || "") !== "") {
            return Qt.rgba(0.8, 0.2, 0, 0.08);
          }
          return Qt.alpha(Color.mSurfaceVariant, 0.3);
        }
        border.width: 1
        border.color: {
          if (pluginApi?.mainInstance?.isAuthenticated) {
            return Qt.rgba(0, 0.8, 0.2, 0.25);
          }
          if ((pluginApi?.mainInstance?.authError || "") !== "") {
            return Qt.rgba(0.8, 0.2, 0, 0.25);
          }
          return Qt.alpha(Style.capsuleBorderColor, 0.5);
        }

        RowLayout {
          id: statusRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          StatusDot {
            active: pluginApi?.mainInstance?.isAuthenticated || false
            error: (pluginApi?.mainInstance?.authError || "") !== ""
          }

          NText {
            Layout.fillWidth: true
            text: {
              if (pluginApi?.mainInstance?.isAuthenticated) {
                return "Authenticated as " + (valueIdentity || "user");
              }
              if ((pluginApi?.mainInstance?.authError || "") !== "") {
                return pluginApi.mainInstance.authError;
              }
              if (pluginApi?.mainInstance?.hasRefreshToken) {
                return "Session available — click Restore";
              }
              return "Not authenticated";
            }
            wrapMode: Text.Wrap
            pointSize: Style.fontSizeS
            color: pluginApi?.mainInstance?.isAuthenticated ? "#22c55e" : Color.mOnSurface
          }
        }
      }

      // Login Form Card
      SettingsCard {
        title: "Sign in to MangaDex"
        icon: "shield-lock"
        subtitle: "Password is used once and never stored"

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          NIcon {
            Layout.alignment: Qt.AlignHCenter
            icon: "shield-lock"
            pointSize: 40
            color: Color.mPrimary
          }

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: "Sign in to MangaDex"
            pointSize: Style.fontSizeL
            font.weight: Font.Bold
            color: Color.mOnSurface
          }

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: "Password is used once and never stored"
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
          }

          SectionLabel { text: "Client ID" }
          StyledField {
            placeholderText: "Client ID (personal-client-...)"
            text: valueClientId
            onTextChanged: valueClientId = text
          }

          SectionLabel { text: "Client Secret" }
          StyledField {
            placeholderText: "Client Secret"
            text: valueClientSecret
            echoMode: TextInput.Password
            onTextChanged: valueClientSecret = text
          }

          SectionLabel { text: "Username / Email" }
          StyledField {
            placeholderText: "MangaDex username or email"
            text: valueIdentity
            onTextChanged: valueIdentity = text
          }

          SectionLabel { text: "Password" }
          StyledField {
            id: settingsPasswordField
            placeholderText: "Password (one-time, not saved)"
            text: loginPasswordInput
            echoMode: TextInput.Password
            onTextChanged: loginPasswordInput = text
            onAccepted: {
              triggerSettingsLogin(loginPasswordInput);
              loginPasswordInput = "";
              settingsPasswordField.clear();
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NButton {
              text: pluginApi?.mainInstance?.authBusy ? "Authenticating..." : "Login"
              enabled: !(pluginApi?.mainInstance?.authBusy || false)
              onClicked: {
                triggerSettingsLogin(loginPasswordInput);
                loginPasswordInput = "";
                settingsPasswordField.clear();
              }
            }

            NButton {
              text: "Restore Session"
              enabled: (pluginApi?.mainInstance?.hasRefreshToken || false) && !(pluginApi?.mainInstance?.authBusy || false)
              onClicked: triggerSettingsLogin("")
            }

            Item { Layout.fillWidth: true }
          }

          // Session Management
          Rectangle {
            Layout.fillWidth: true
            implicitHeight: sessionRow.implicitHeight + Style.marginS * 2
            radius: Style.radiusS
            color: Qt.alpha(Color.mSurface, 0.3)

            RowLayout {
              id: sessionRow
              anchors.fill: parent
              anchors.margins: Style.marginS
              spacing: Style.marginM

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                NText {
                  text: "Remember session"
                  pointSize: Style.fontSizeS
                  color: Color.mOnSurface
                }

                NText {
                  text: "Store refresh token for automatic login"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurfaceVariant
                }
              }

              NToggle {
                checked: valueRememberSession
                onToggled: checked => valueRememberSession = checked
              }

              NButton {
                text: "Clear Session"
                onClicked: {
                  if (pluginApi?.mainInstance) {
                    pluginApi.mainInstance.clearSession(true);
                  }
                }
              }
            }
          }
        }
      }

      Item { Layout.fillHeight: true }
    }

    // ===== Reader Tab =====
    ColumnLayout {
      spacing: Style.marginM

      SettingsCard {
        title: "Image Quality"
        icon: "image"
        subtitle: "Data Saver uses less bandwidth"

        SettingRow {
          label: "Image quality"
          description: "Lower quality saves bandwidth"

          StyledComboBox {
            Layout.preferredWidth: 160
            model: ["Data Saver", "Original"]
            currentIndex: valueQuality === "data" ? 1 : 0
            onActivated: valueQuality = index === 1 ? "data" : "data-saver"
          }
        }
      }

      SettingsCard {
        title: "Language"
        icon: "globe"
        subtitle: "Preferred language for titles and chapters"

        SettingRow {
          label: "Preferred language"
          description: "Primary language code (e.g., en)"

          StyledField {
            Layout.preferredWidth: 100
            placeholderText: "en"
            text: valuePreferredLanguage
            onTextChanged: valuePreferredLanguage = text
          }
        }

        SectionLabel { text: "Translated languages" }
        StyledField {
          placeholderText: "en, ja, ko"
          text: valueTranslatedLanguagesCsv
          onTextChanged: valueTranslatedLanguagesCsv = text
        }
        NText {
          Layout.fillWidth: true
          text: "Comma-separated language codes for chapter filtering"
          pointSize: Style.fontSizeXS
          color: Color.mOnSurfaceVariant
        }
      }

      SettingsCard {
        title: "Content Filters"
        icon: "filter"
        subtitle: "Select which content ratings to show"

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          SettingRow {
            label: "Safe"
            NToggle {
              checked: ratingSafe
              onToggled: checked => ratingSafe = checked
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.alpha(Style.capsuleBorderColor, 0.3)
          }

          SettingRow {
            label: "Suggestive"
            NToggle {
              checked: ratingSuggestive
              onToggled: checked => ratingSuggestive = checked
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.alpha(Style.capsuleBorderColor, 0.3)
          }

          SettingRow {
            label: "Erotica"
            NToggle {
              checked: ratingErotica
              onToggled: checked => ratingErotica = checked
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.alpha(Style.capsuleBorderColor, 0.3)
          }

          SettingRow {
            label: "Pornographic"
            NToggle {
              checked: ratingPornographic
              onToggled: checked => ratingPornographic = checked
            }
          }
        }
      }

      SettingsCard {
        title: "Panel Layout"
        icon: "layout-sidebar"
        subtitle: "Customize reader panel behavior"

        SettingRow {
          label: "Reader side"
          description: "Which side the panel opens from"

          StyledComboBox {
            Layout.preferredWidth: 160
            model: ["Left", "Right"]
            currentIndex: valuePanelPosition === "left" ? 0 : 1
            onActivated: valuePanelPosition = currentText.toLowerCase()
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Qt.alpha(Style.capsuleBorderColor, 0.3)
        }

        SettingRow {
          label: "Minimal controls"
          description: "Compact top bar in reader"

          NToggle {
            checked: valueMinimalControls
            onToggled: checked => valueMinimalControls = checked
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Qt.alpha(Style.capsuleBorderColor, 0.3)
        }

        SettingRow {
          label: "Collapse browse rail"
          description: "Start with sidebar hidden"

          NToggle {
            checked: valueUtilityCollapsed
            onToggled: checked => valueUtilityCollapsed = checked
          }
        }
      }

      Item { Layout.fillHeight: true }
    }

    // ===== Advanced Tab =====
    ColumnLayout {
      spacing: Style.marginM

      SettingsCard {
        title: "Panel Dimensions"
        icon: "maximize"
        subtitle: "Configure reader panel size"

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          SettingRow {
            label: "Panel width"
            description: widthIsValid
                ? ("Valid range: " + valuePanelWidthMin + " to " + valuePanelWidthMax + " px")
                : ("Width will be clamped to " + normalizeWidth(valuePanelWidth) + " px")

            StyledField {
              Layout.preferredWidth: 100
              text: String(valuePanelWidth)
              validator: IntValidator { bottom: root.valuePanelWidthMin; top: root.valuePanelWidthMax }
              onEditingFinished: {
                valuePanelWidth = Number(text);
                text = String(normalizeWidth(valuePanelWidth));
              }
            }
          }

          Slider {
            id: widthSlider
            Layout.fillWidth: true
            from: valuePanelWidthMin
            to: valuePanelWidthMax
            value: valuePanelWidth
            stepSize: 10
            onMoved: valuePanelWidth = Math.round(value)
            onValueChanged: {
              if (pressed) {
                valuePanelWidth = Math.round(value);
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NText {
              text: valuePanelWidthMin + " px"
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }

            Item { Layout.fillWidth: true }

            NText {
              text: Math.round(widthSlider.value) + " px"
              pointSize: Style.fontSizeXS
              color: Color.mPrimary
              font.weight: Font.Medium
            }

            Item { Layout.fillWidth: true }

            NText {
              text: valuePanelWidthMax + " px"
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
            }
          }
        }
      }

      SettingsCard {
        title: "Network"
        icon: "refresh"
        subtitle: "Tune pagination and retry behavior"

        SettingRow {
          label: "Search page size"
          description: "Results per page (1-100)"

          StyledField {
            Layout.preferredWidth: 80
            text: String(valueSearchPageSize)
            validator: IntValidator { bottom: 1; top: 100 }
            onEditingFinished: valueSearchPageSize = Math.max(1, Math.min(100, Number(text)))
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Qt.alpha(Style.capsuleBorderColor, 0.3)
        }

        SettingRow {
          label: "Rate-limit cooldown"
          description: "Seconds to wait after HTTP 429"

          StyledField {
            Layout.preferredWidth: 80
            text: String(valueCooldownSeconds)
            validator: IntValidator { bottom: 1; top: 120 }
            onEditingFinished: valueCooldownSeconds = Math.max(1, Number(text))
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Qt.alpha(Style.capsuleBorderColor, 0.3)
        }

        SettingRow {
          label: "Request pacing"
          description: "Minimum delay between API calls (ms)"

          StyledField {
            Layout.preferredWidth: 80
            text: String(valueRequestPacingMs)
            validator: IntValidator { bottom: 0; top: 3000 }
            onEditingFinished: valueRequestPacingMs = Math.max(0, Math.min(3000, Number(text)))
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Qt.alpha(Style.capsuleBorderColor, 0.3)
        }

        SettingRow {
          label: "Max retry attempts"
          description: "Retries for transient API failures"

          StyledField {
            Layout.preferredWidth: 80
            text: String(valueMaxRetryAttempts)
            validator: IntValidator { bottom: 0; top: 5 }
            onEditingFinished: valueMaxRetryAttempts = Math.max(0, Math.min(5, Number(text)))
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Qt.alpha(Style.capsuleBorderColor, 0.3)
        }

        SettingRow {
          label: "Retry base delay"
          description: "Base backoff delay in milliseconds"

          StyledField {
            Layout.preferredWidth: 80
            text: String(valueRetryBaseDelayMs)
            validator: IntValidator { bottom: 100; top: 10000 }
            onEditingFinished: valueRetryBaseDelayMs = Math.max(100, Math.min(10000, Number(text)))
          }
        }
      }

      SettingsCard {
        title: "Diagnostics"
        icon: "bug"
        subtitle: "Control runtime log verbosity"

        SettingRow {
          label: "Logging mode"
          description: "Off keeps only critical errors, Verbose logs full request and reader lifecycle"

          StyledComboBox {
            Layout.preferredWidth: 180
            model: ["Off", "Normal", "Verbose"]
            currentIndex: valueLoggingMode === "off" ? 0 : (valueLoggingMode === "verbose" ? 2 : 1)
            onActivated: {
              if (currentIndex === 0) {
                valueLoggingMode = "off";
              } else if (currentIndex === 2) {
                valueLoggingMode = "verbose";
              } else {
                valueLoggingMode = "normal";
              }
            }
          }
        }
      }

      Item { Layout.fillHeight: true }
    }
  }

  // ===== Bottom Actions =====

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NButton {
      text: "Save All"
      onClicked: saveSettings(true)
    }

    NButton {
      text: "Save & Apply"
      onClicked: {
        saveSettings(false);
        applyLayoutNow();
      }
    }

    Item { Layout.fillWidth: true }
  }
}