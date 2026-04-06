import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import "Diagnostics.js" as Diagnostics
import "core/ReaderRecovery.js" as ReaderRecovery
import "utils/IconResolver.js" as IconResolver
import "components" as Components

Item {
  id: root
  anchors.fill: parent
  focus: true

  property var pluginApi: null
  property ShellScreen screen
  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property var activeScreen: screen ?? pluginApi?.panelOpenScreen ?? null

  readonly property string panelSide: mainInstance?.panelSide ?? "right"
  readonly property bool panelAnchorRight: panelSide === "right"
  readonly property bool panelAnchorLeft: panelSide === "left"
  readonly property bool panelAnchorTop: true
  readonly property bool panelAnchorBottom: true
  readonly property bool panelAnchorHorizontalCenter: false
  readonly property bool panelAnchorVerticalCenter: false

  readonly property var geometryPlaceholder: panelSurface
  readonly property bool allowAttach: false

  property real contentPreferredWidth: mainInstance?.panelWidthPx
      ?? ((pluginApi?.pluginSettings?.panelWidth
          ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelWidth
          ?? 1120) * Style.uiScaleRatio)
  property real contentPreferredHeight: {
    // Full screen height for side panel
    var screenHeight = Number(activeScreen?.height || 0);
    if (screenHeight > 0) {
      return screenHeight;
    }
    return 1080 * Style.uiScaleRatio;
  }

  // Auto-expand utility rail when no chapter is selected so search is always accessible
  readonly property bool utilityCollapsed: {
    if (!mainInstance) return false;
    return mainInstance.readerUtilityCollapsed && mainInstance.currentChapter;
  }
  readonly property bool minimalControls: mainInstance?.readerMinimalControls ?? true
  readonly property int readerRenderEpoch: mainInstance?.readerRenderEpoch ?? 0

  property bool showFollowedFeed: mainInstance?.showFollowedFeed ?? false
  property var readerAnchorState: ({
    chapterId: "",
    pageIdentity: "",
    pageIndex: 0,
    offsetRatio: 0,
    scrollY: 0,
    timestampMs: 0
  })
  property var pendingAnchorRestore: null
  property string pendingAnchorReason: ""
  property int pendingAnchorAttempts: 0

  Timer {
    id: anchorRestoreTimer
    interval: 140
    repeat: false
    onTriggered: root.tryRestoreReaderAnchor()
  }

  Component.onCompleted: {
    if (mainInstance && mainInstance.notifyPanelShown) {
      mainInstance.notifyPanelShown();
    }
    Qt.callLater(function() {
      root.scheduleAnchorRestore("panel_open", 180);
    });
  }

  Component.onDestruction: {
    if (mainInstance && mainInstance.notifyPanelHidden) {
      mainInstance.notifyPanelHidden();
    }
  }

  function clampUnitInterval(value) {
    var numeric = Number(value);
    if (isNaN(numeric)) {
      numeric = 0;
    }
    return Math.max(0, Math.min(1, numeric));
  }

  function resolveControlIcon(iconName, fallbackIcon) {
    return IconResolver.resolveIcon(iconName, fallbackIcon || "settings", Diagnostics.warn);
  }

  function normalizeAnchorState(anchorCandidate, chapterIdFallback) {
    var source = anchorCandidate && typeof anchorCandidate === "object" ? anchorCandidate : {};
    var chapterIdValue = String(source.chapterId || chapterIdFallback || "").trim();
    if (chapterIdValue === "") {
      return null;
    }

    var pageIndexValue = Number(source.pageIndex);
    if (isNaN(pageIndexValue) || pageIndexValue < 0) {
      pageIndexValue = 0;
    }

    var scrollYValue = Number(source.scrollY);
    if (isNaN(scrollYValue) || scrollYValue < 0) {
      scrollYValue = 0;
    }

    return {
      chapterId: chapterIdValue,
      pageIdentity: String(source.pageIdentity || "").trim(),
      pageIndex: Math.round(pageIndexValue),
      offsetRatio: clampUnitInterval(source.offsetRatio),
      scrollY: scrollYValue,
      timestampMs: Number(source.timestampMs || Date.now())
    };
  }

  function captureReaderAnchor(reason, persistToMain) {
    if (!mainInstance || !mainInstance.currentChapter || !readerScroll || !readerScroll.contentItem || !pageRepeater) {
      return;
    }

    var viewportTop = Number(readerScroll.contentItem.contentY || 0);
    var bestItem = null;
    var bestIndex = 0;
    var bestDistance = Number.MAX_VALUE;

    for (var i = 0; i < pageRepeater.count; i++) {
      var item = pageRepeater.itemAt(i);
      if (!item || Number(item.height || 0) <= 0) {
        continue;
      }

      var itemTop = Number(item.y || 0);
      var itemBottom = itemTop + Number(item.height || 0);
      var distance = (viewportTop >= itemTop && viewportTop <= itemBottom)
          ? 0
          : Math.min(Math.abs(viewportTop - itemTop), Math.abs(viewportTop - itemBottom));

      if (distance < bestDistance) {
        bestDistance = distance;
        bestItem = item;
        bestIndex = i;
      }
    }

    if (!bestItem && pageRepeater.count > 0) {
      bestItem = pageRepeater.itemAt(0);
      bestIndex = 0;
    }

    if (!bestItem) {
      return;
    }

    var modelData = bestItem.modelData || {};
    var itemTopValue = Number(bestItem.y || 0);
    var itemHeightValue = Math.max(1, Number(bestItem.height || 0));
    var offsetRatioValue = clampUnitInterval((viewportTop - itemTopValue) / itemHeightValue);

    var anchor = normalizeAnchorState({
      chapterId: mainInstance.currentChapter.id,
      pageIdentity: String(modelData.pageIdentity || modelData.canonicalSource || modelData.source || ""),
      pageIndex: bestIndex,
      offsetRatio: offsetRatioValue,
      scrollY: viewportTop,
      timestampMs: Date.now()
    }, mainInstance.currentChapter.id);

    if (!anchor) {
      return;
    }

    readerAnchorState = anchor;
    if (mainInstance.updateReaderViewportAnchor) {
      mainInstance.updateReaderViewportAnchor(anchor, !!persistToMain);
    }

    Diagnostics.debug("reader.anchor.capture", {
      chapterId: anchor.chapterId,
      pageIdentity: anchor.pageIdentity,
      pageIndex: anchor.pageIndex,
      offsetRatio: anchor.offsetRatio,
      reason: reason || "scroll"
    }, "Captured reader viewport anchor");
  }

  function resolveAnchorTarget(anchorState) {
    if (!anchorState || !pageRepeater) {
      return null;
    }

    var targetIdentity = String(anchorState.pageIdentity || "").trim();
    if (targetIdentity !== "") {
      for (var i = 0; i < pageRepeater.count; i++) {
        var item = pageRepeater.itemAt(i);
        if (!item) {
          continue;
        }
        var data = item.modelData || {};
        var identity = String(data.pageIdentity || data.canonicalSource || data.source || "");
        if (identity === targetIdentity) {
          return { item: item, index: i };
        }
      }
    }

    var fallbackIndex = Math.round(Number(anchorState.pageIndex || 0));
    if (fallbackIndex >= 0 && fallbackIndex < pageRepeater.count) {
      var fallbackItem = pageRepeater.itemAt(fallbackIndex);
      if (fallbackItem) {
        return { item: fallbackItem, index: fallbackIndex };
      }
    }

    if (pageRepeater.count > 0) {
      var first = pageRepeater.itemAt(0);
      if (first) {
        return { item: first, index: 0 };
      }
    }

    return null;
  }

  function scheduleAnchorRestore(reason, delayMs) {
    if (!mainInstance || !mainInstance.currentChapter || !readerScroll || !readerScroll.contentItem) {
      return;
    }

    var chapterId = String(mainInstance.currentChapter.id || "");
    if (chapterId === "") {
      return;
    }

    var sourceAnchor = null;
    if (mainInstance.getReaderViewportAnchor) {
      sourceAnchor = mainInstance.getReaderViewportAnchor(chapterId);
    }
    if (!sourceAnchor) {
      sourceAnchor = readerAnchorState;
    }

    var normalized = normalizeAnchorState(sourceAnchor, chapterId);
    if (!normalized || normalized.chapterId !== chapterId) {
      return;
    }

    pendingAnchorRestore = normalized;
    pendingAnchorReason = String(reason || "layout_change");
    pendingAnchorAttempts = 0;
    anchorRestoreTimer.interval = Math.max(60, Number(delayMs || 140));
    anchorRestoreTimer.restart();
  }

  function tryRestoreReaderAnchor() {
    if (!pendingAnchorRestore || !mainInstance || !mainInstance.currentChapter || !readerScroll || !readerScroll.contentItem) {
      return;
    }

    if (pendingAnchorRestore.chapterId !== String(mainInstance.currentChapter.id || "")) {
      pendingAnchorRestore = null;
      return;
    }

    var target = resolveAnchorTarget(pendingAnchorRestore);
    if (!target || !target.item || Number(target.item.height || 0) <= 0) {
      if (pendingAnchorAttempts < 8) {
        pendingAnchorAttempts += 1;
        anchorRestoreTimer.interval = 100;
        anchorRestoreTimer.restart();
      } else {
        pendingAnchorRestore = null;
      }
      return;
    }

    var itemTop = Number(target.item.y || 0);
    var itemHeight = Math.max(1, Number(target.item.height || 0));
    var desiredY = itemTop + itemHeight * clampUnitInterval(pendingAnchorRestore.offsetRatio);
    var maxY = Math.max(0, Number(readerScroll.contentItem.contentHeight || 0) - Number(readerScroll.height || 0));
    var clampedY = Math.max(0, Math.min(maxY, desiredY));

    readerScroll.contentItem.contentY = clampedY;
    pendingAnchorRestore = null;
    Qt.callLater(updateVisiblePages);
    captureReaderAnchor("restore_applied", false);

    Diagnostics.debug("reader.anchor.restore", {
      chapterId: mainInstance.currentChapter.id,
      pageIndex: target.index,
      contentY: Math.round(clampedY),
      reason: pendingAnchorReason
    }, "Restored reader viewport anchor after layout/model transition");
  }

  property bool panelClosing: false

  function closePanel() {
    if (!pluginApi || panelClosing) { return; }

    panelClosing = true;
    panelSurface.x = panelSurface.offscreenX;
    closePanelTimer.start();
  }

  function performClosePanel() {
    if (!pluginApi) { return; }

    if (screen) {
      pluginApi.closePanel(screen);
      return;
    }

    if (pluginApi.withCurrentScreen) {
      pluginApi.withCurrentScreen(function(currentScreen) {
        pluginApi.closePanel(currentScreen);
      });
    }
  }

  Timer {
    id: closePanelTimer
    interval: 260
    repeat: false
    onTriggered: root.performClosePanel()
  }

  function setUtilityCollapsed(nextCollapsed) {
    if (!mainInstance) { return; }
    captureReaderAnchor("before_utility_toggle", true);
    mainInstance.setReaderUtilityCollapsed(nextCollapsed, true);
    scheduleAnchorRestore("after_utility_toggle", 150);
  }

  function setMinimalControls(nextMinimal) {
    if (!mainInstance) { return; }
    captureReaderAnchor("before_controls_toggle", true);
    mainInstance.setReaderMinimalControls(nextMinimal, true);
    scheduleAnchorRestore("after_controls_toggle", 150);
  }

  Connections {
    target: mainInstance
    enabled: target !== null

    function onPageUrlsChanged() {
      Qt.callLater(updateVisiblePages);
      scheduleAnchorRestore("page_model_changed", 160);
      Diagnostics.debug("reader.viewport.model_changed", {
        chapterId: mainInstance?.currentChapter?.id || "",
        pageCount: mainInstance?.pageUrls?.length || 0
      }, "Page model changed; recalculating viewport activation");
    }

    function onCurrentChapterChanged() {
      Qt.callLater(updateVisiblePages);
      scheduleAnchorRestore("chapter_changed", 180);
    }

    function onReaderRenderEpochChanged() {
      Qt.callLater(updateVisiblePages);
      scheduleAnchorRestore("render_epoch_changed", 120);
    }

    function onReaderTransitionSettleEpochChanged() {
      Qt.callLater(function() {
        updateVisiblePages();
        scheduleAnchorRestore("transition_settle", 140);
        var recoveredCount = recoverVisibleLoadingPages("transition_settle");
        Diagnostics.debug("reader.transition.reconcile", {
          chapterId: mainInstance?.currentChapter?.id || "",
          recoveredCount: recoveredCount,
          settleEpoch: mainInstance?.readerTransitionSettleEpoch || 0
        }, "Ran post-settle viewport reconciliation");
      });
    }
  }

  Keys.onEscapePressed: { closePanel(); }

  Keys.onLeftPressed: {
    if (mainInstance) { mainInstance.openPreviousChapter(); }
  }

  Keys.onRightPressed: {
    if (mainInstance) { mainInstance.openNextChapter(); }
  }

  Keys.onUpPressed: {
    if (readerScroll.visible) {
      readerScroll.contentItem.contentY = Math.max(0, readerScroll.contentItem.contentY - readerScroll.height * 0.8);
    }
  }

  Keys.onDownPressed: {
    if (readerScroll.visible) {
      readerScroll.contentItem.contentY = Math.min(
        readerScroll.contentItem.contentHeight - readerScroll.height,
        readerScroll.contentItem.contentY + readerScroll.height * 0.8
      );
    }
  }

  Keys.onSpacePressed: {
    if (readerScroll.visible) {
      readerScroll.contentItem.contentY = Math.min(
        readerScroll.contentItem.contentHeight - readerScroll.height,
        readerScroll.contentItem.contentY + readerScroll.height * 0.9
      );
    }
  }

  // ===== Inline Components =====

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
        icon: resolveControlIcon("alert-triangle", "settings")
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

  component StyledField: TextField {
    id: styledField

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
      border.color: styledField.activeFocus ? Qt.alpha(Color.mPrimary, 0.9) : Qt.alpha(Style.capsuleBorderColor, 0.65)

      Behavior on border.color {
        ColorAnimation { duration: 150 }
      }
    }
  }

  component StyledComboBox: ComboBox {
    id: styledCombo

    property bool popupOpen: styledCombo.popup.visible

    Layout.preferredWidth: 140
    implicitHeight: 36

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
      icon: resolveControlIcon("chevron-down", "chevron-right")
      pointSize: Style.fontSizeXS
      color: Color.mOnSurfaceVariant
      rotation: styledCombo.popupOpen ? 180 : 0

      Behavior on rotation {
        NumberAnimation { duration: 200 }
      }
    }
  }

  component FilterChip: Rectangle {
    property string label: ""
    property bool active: false

    implicitWidth: chipLabel.implicitWidth + Style.marginM * 2
    implicitHeight: 28
    radius: Style.radiusS
    color: active ? Qt.alpha(Color.mPrimary, 0.2) : Qt.alpha(Color.mSurface, 0.3)
    border.width: 1
    border.color: active ? Qt.alpha(Color.mPrimary, 0.5) : Qt.alpha(Style.capsuleBorderColor, 0.4)

    NText {
      id: chipLabel
      anchors.centerIn: parent
      text: label
      pointSize: Style.fontSizeXS
      color: active ? Color.mPrimary : Color.mOnSurfaceVariant
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: parent.color = active ? Qt.alpha(Color.mPrimary, 0.25) : Qt.alpha(Color.mSurface, 0.5)
      onExited: parent.color = active ? Qt.alpha(Color.mPrimary, 0.2) : Qt.alpha(Color.mSurface, 0.3)
    }
  }

  // ===== Main Panel Surface =====

  Rectangle {
    id: panelSurface
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.max(560 * Style.uiScaleRatio, Math.min(parent.width, root.contentPreferredWidth))

    property real targetX: root.panelAnchorRight ? parent.width - width : 0
    property real offscreenX: root.panelAnchorRight ? parent.width : -width
    property bool animationReady: false

    x: targetX

    Behavior on x {
      enabled: panelSurface.animationReady
      NumberAnimation {
        duration: 220
        easing.type: Easing.OutCubic
      }
    }

    Component.onCompleted: {
      panelSurface.x = panelSurface.offscreenX;
      panelSurface.animationReady = true;
      panelSurface.x = Qt.binding(function() { return panelSurface.targetX; });
    }

    color: Qt.alpha(Color.mSurface, 0.985)
    border.width: 1
    border.color: Qt.alpha(Style.capsuleBorderColor, 0.9)
    clip: true

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginS

      // ===== Top Control Bar =====
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        radius: Style.radiusM
        color: Qt.alpha(Color.mSurfaceVariant, 0.5)
        border.width: 1
        border.color: Qt.alpha(Style.capsuleBorderColor, 0.6)

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.marginS
          anchors.rightMargin: Style.marginS
          spacing: Style.marginXS

          // Left group
          RowLayout {
            spacing: Style.marginXS

            NIconButton {
              icon: resolveControlIcon(root.utilityCollapsed ? "layout-sidebar-left-expand" : "layout-sidebar-left-collapse", "layout-sidebar-right-expand")
              tooltipText: root.utilityCollapsed ? "Show sidebar" : "Hide sidebar"
              onClicked: root.setUtilityCollapsed(!root.utilityCollapsed)
            }

            Rectangle {
              Layout.preferredWidth: 1
              Layout.preferredHeight: 20
              color: Qt.alpha(Style.capsuleBorderColor, 0.5)
            }
          }

          // Center - Chapter label and API Status
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            
            NText {
              Layout.fillWidth: true
              text: mainInstance?.currentChapter
                  ? mainInstance.chapterLabel(mainInstance.currentChapter)
                  : "No chapter selected"
              color: Color.mOnSurface
              pointSize: Style.fontSizeS
              elide: Text.ElideMiddle
              horizontalAlignment: Text.AlignHCenter
            }

            NText {
              Layout.fillWidth: true
              visible: mainInstance?.showApiStatus && mainInstance?.apiStatusText !== ""
              text: mainInstance?.apiStatusText || ""
              color: Color.mPrimary
              pointSize: Style.fontSizeXS
              elide: Text.ElideMiddle
              horizontalAlignment: Text.AlignHCenter
            }
          }

          // Right group
          RowLayout {
            spacing: Style.marginXS

            NButton {
              text: mainInstance?.qualityMode === "data" ? "High Quality" : "Data Saver"
              icon: mainInstance?.qualityMode === "data" ? resolveControlIcon("photo-up", "image") : resolveControlIcon("photo-down", "image")
              tooltipText: "Toggle Image Quality"
              onClicked: {
                if (mainInstance) {
                  mainInstance.qualityMode = mainInstance.qualityMode === "data" ? "data-saver" : "data";
                }
              }
            }

            StyledComboBox {
              id: statusSelector

              readonly property var statusLabels: ({
                "": "Set status...",
                "reading": "Reading",
                "on_hold": "On Hold",
                "plan_to_read": "Plan to Read",
                "dropped": "Dropped",
                "re_reading": "Re-reading",
                "completed": "Completed"
              })

              model: ["", "reading", "on_hold", "plan_to_read", "dropped", "re_reading", "completed"]
              displayText: statusLabels[currentText] || currentText

              currentIndex: {
                var target = mainInstance?.mangaReadingStatus || "";
                for (var i = 0; i < model.length; i++) {
                  if (model[i] === target) { return i; }
                }
                return 0;
              }
              onActivated: {
                if (mainInstance) {
                  mainInstance.setMangaReadingStatus(model[currentIndex]);
                }
              }

              delegate: ItemDelegate {
                width: statusSelector.width
                contentItem: NText {
                  text: statusSelector.statusLabels[modelData] || modelData
                  pointSize: Style.fontSizeS
                  color: Color.mOnSurface
                }
                highlighted: statusSelector.highlightedIndex === index
              }

              ToolTip.visible: hovered && currentIndex === 0
              ToolTip.text: "Set your reading status for this manga"
            }

            NIconButton {
              icon: resolveControlIcon("x", "settings")
              tooltipText: "Close reader"
              onClicked: root.closePanel()
            }
          }
        }
      }

      // ===== Error Display =====
      ErrorBanner {
        message: mainInstance?.readerError || ""
      }

      // ===== Main Content =====
      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Style.marginS

        // ===== Utility Rail =====
        Rectangle {
          id: utilityRail
          Layout.fillHeight: true
          Layout.preferredWidth: root.utilityCollapsed
              ? 0
              : Math.max(280, Math.min(420, panelSurface.width * (root.minimalControls ? 0.34 : 0.38)))
          Layout.minimumWidth: 0
          visible: !root.utilityCollapsed
          clip: true
          radius: Style.radiusM
          color: Qt.alpha(Color.mSurfaceVariant, 0.34)
          border.width: 1
          border.color: Qt.alpha(Style.capsuleBorderColor, 0.65)

          Behavior on Layout.preferredWidth {
            NumberAnimation {
              duration: 160
              easing.type: Easing.InOutQuad
            }
          }

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginS
            spacing: Style.marginS

            // ===== Search Section =====
            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: Style.radiusS
              color: Qt.alpha(Color.mSurface, 0.45)
              border.width: 1
              border.color: Qt.alpha(Style.capsuleBorderColor, 0.45)

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: Style.marginS
                spacing: Style.marginS

                // Search field with icon
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginXS

                  NIcon {
                    icon: resolveControlIcon("search", "settings")
                    pointSize: Style.fontSizeS
                    color: Color.mOnSurfaceVariant
                  }

                  StyledField {
                    placeholderText: "Search manga title"
                    text: mainInstance?.searchQuery || ""
                    onTextChanged: {
                      if (mainInstance) { mainInstance.searchQuery = text; }
                    }
                    onAccepted: {
                      if (mainInstance) { mainInstance.searchManga(true); }
                    }
                  }
                }

                // Filter chips
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginXS

                  FilterChip {
                    label: "Feed"
                    active: root.showFollowedFeed
                    MouseArea {
                      anchors.fill: parent
                      onClicked: {
                        if (mainInstance && mainInstance.isAuthenticated) {
                          mainInstance.loadFollowedFeed();
                        } else if (mainInstance) {
                          mainInstance.followedError = "Sign in from settings to load followed feed.";
                        }
                      }
                    }
                  }

                  Item { Layout.fillWidth: true }

                  NText {
                    visible: mainInstance?.isLoadingSearch || false
                    text: "Cancel"
                    color: Color.mError
                    pointSize: Style.fontSizeXS
                    font.underline: true

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (mainInstance && mainInstance.cancelSearch) {
                          mainInstance.cancelSearch();
                        }
                      }
                    }
                  }
                }

                ErrorBanner {
                  message: mainInstance?.searchError || ""
                }

                // ===== Manga Results =====
                NText {
                  text: "Manga Results"
                  pointSize: Style.fontSizeS
                  font.weight: Font.DemiBold
                  color: Color.mOnSurface
                }

                Item {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Math.max(140, parent.height * 0.45)
                  clip: true

                  ListView {
                    id: mangaList
                    anchors.fill: parent
                    clip: true
                    spacing: 4
                    model: mainInstance?.searchResults || []

                    add: Transition {
                      NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                    }
                    displaced: Transition {
                      NumberAnimation { properties: "y"; duration: 150; easing.type: Easing.OutCubic }
                    }

                    delegate: Rectangle {
                      id: mangaDelegate
                      required property var modelData
                      property bool hovered: false
                      property bool isSelected: (mainInstance?.selectedManga?.id || "") === modelData.id

                      width: mangaList.width
                      height: 66
                      radius: Style.radiusS
                      color: hovered
                          ? Qt.alpha(Color.mHover, 0.45)
                          : (isSelected ? Qt.alpha(Color.mPrimary, 0.15) : Qt.alpha(Color.mSurface, 0.5))
                      border.width: 1
                      border.color: hovered
                          ? Qt.alpha(Color.mPrimary, 0.65)
                          : Qt.alpha(Style.capsuleBorderColor, 0.55)

                      // Left accent bar for selection
                      Rectangle {
                        visible: isSelected
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3
                        radius: 2
                        color: Color.mPrimary
                      }

                      RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: isSelected ? Style.marginM : Style.marginS
                        anchors.rightMargin: Style.marginS
                        anchors.topMargin: Style.marginS
                        anchors.bottomMargin: Style.marginS
                        spacing: Style.marginS

                        // Cover thumbnail
                        Item {
                          Layout.preferredWidth: 40
                          Layout.preferredHeight: 56
                          clip: true

                          Image {
                            id: coverImage
                            anchors.fill: parent
                            source: mainInstance ? mainInstance.mangaCoverUrl(modelData) : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            visible: status === Image.Ready
                          }

                          Rectangle {
                            anchors.fill: parent
                            radius: Style.radiusXS
                            color: Qt.alpha(Color.mSurfaceVariant, 0.5)
                            visible: coverImage.status !== Image.Ready

                            NIcon {
                              anchors.centerIn: parent
                              icon: resolveControlIcon("book-2", "settings")
                              pointSize: Style.fontSizeS
                              color: Color.mPrimary
                            }
                          }
                        }

                        ColumnLayout {
                          Layout.fillWidth: true
                          spacing: 2

                          NText {
                            Layout.fillWidth: true
                            text: mainInstance ? mainInstance.mangaTitle(modelData) : ""
                            elide: Text.ElideRight
                            color: Color.mOnSurface
                            pointSize: Style.fontSizeS
                            font.weight: Font.Medium
                          }

                          RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.marginXS

                            Rectangle {
                              visible: modelData?.attributes?.status
                              implicitWidth: statusBadge.implicitWidth + 8
                              implicitHeight: 16
                              radius: 8
                              color: Qt.alpha(Color.mPrimary, 0.2)

                              NText {
                                id: statusBadge
                                anchors.centerIn: parent
                                text: modelData?.attributes?.status || ""
                                pointSize: Style.fontSizeXS - 1
                                color: Color.mPrimary
                              }
                            }

                            NText {
                              Layout.fillWidth: true
                              text: modelData?.attributes?.author || ""
                              elide: Text.ElideRight
                              color: Color.mOnSurfaceVariant
                              pointSize: Style.fontSizeXS
                            }
                          }
                        }
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: mangaDelegate.hovered = true
                        onExited: mangaDelegate.hovered = false
                        onClicked: {
                          if (mainInstance) { mainInstance.selectManga(modelData); }
                        }
                      }
                    }
                  }

                  Rectangle {
                    anchors.fill: parent
                    visible: (mainInstance?.searchResults?.length || 0) === 0 && !(mainInstance?.isLoadingSearch || false)
                    color: "transparent"

                    NText {
                      anchors.centerIn: parent
                      text: "Search to load manga"
                      color: Color.mOnSurfaceVariant
                      pointSize: Style.fontSizeXS
                    }
                  }
                }

                // Load more link
                NText {
                  Layout.fillWidth: true
                  visible: (mainInstance?.hasMoreSearch || false) && !(mainInstance?.isLoadingSearch || false)
                  text: "Load more results"
                  color: Color.mPrimary
                  pointSize: Style.fontSizeXS
                  font.underline: true

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (mainInstance) { mainInstance.loadMoreSearch(); }
                    }
                  }
                }

                // ===== Chapter List =====
                NText {
                  text: mainInstance?.showFollowedFeed ? "Followed Feed Chapters" : "Chapters"
                  pointSize: Style.fontSizeS
                  font.weight: Font.DemiBold
                  color: Color.mOnSurface
                }

                ErrorBanner {
                  message: (mainInstance?.followedError || "") !== ""
                      ? (mainInstance?.followedError || "")
                      : (mainInstance?.chapterError || "")
                }

                Item {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  clip: true

                  ListView {
                    id: chapterList
                    anchors.fill: parent
                    clip: true
                    spacing: 4
                    model: mainInstance?.chapters || []

                    add: Transition {
                      NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                    }
                    displaced: Transition {
                      NumberAnimation { properties: "y"; duration: 150; easing.type: Easing.OutCubic }
                    }

                    delegate: Rectangle {
                      id: chapterDelegate
                      required property var modelData
                      property bool hovered: false
                      property bool isCurrent: (mainInstance?.currentChapter?.id || "") === modelData.id
                      property bool isRead: mainInstance?.chapterIsRead(modelData.id) || false

                      width: chapterList.width
                      height: 56
                      radius: Style.radiusS
                      color: hovered
                          ? Qt.alpha(Color.mHover, 0.4)
                          : (isCurrent ? Qt.alpha(Color.mPrimary, 0.15) : Qt.alpha(Color.mSurface, 0.48))
                      border.width: 1
                      border.color: hovered
                          ? Qt.alpha(Color.mPrimary, 0.65)
                          : Qt.alpha(Style.capsuleBorderColor, 0.55)

                      // Left accent bar for current chapter
                      Rectangle {
                        visible: isCurrent
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 3
                        radius: 2
                        color: Color.mPrimary
                      }

                      RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: isCurrent ? Style.marginM : Style.marginS
                        anchors.rightMargin: Style.marginS
                        spacing: Style.marginS

                        NIcon {
                          icon: resolveControlIcon(isRead ? "check" : "circle", "settings")
                          pointSize: Style.fontSizeS
                          color: isRead ? "#22c55e" : Color.mOnSurfaceVariant
                        }

                        ColumnLayout {
                          Layout.fillWidth: true
                          spacing: 2

                          NText {
                            Layout.fillWidth: true
                            text: mainInstance ? mainInstance.chapterLabel(modelData) : ""
                            color: Color.mOnSurface
                            pointSize: Style.fontSizeXS
                            elide: Text.ElideRight
                          }

                          NText {
                            Layout.fillWidth: true
                            visible: modelData?.relationships?.find(r => r.type === "scanlation_group")?.attributes?.name
                            text: modelData?.relationships?.find(r => r.type === "scanlation_group")?.attributes?.name || ""
                            color: Color.mOnSurfaceVariant
                            pointSize: Style.fontSizeXS - 1
                            elide: Text.ElideRight
                          }
                        }

                        NIcon {
                          icon: resolveControlIcon("chevron-right", "settings")
                          pointSize: Style.fontSizeXS
                          color: Color.mOnSurfaceVariant
                        }
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: chapterDelegate.hovered = true
                        onExited: chapterDelegate.hovered = false
                        onClicked: {
                          if (mainInstance) { mainInstance.openChapter(modelData); }
                        }
                      }
                    }
                  }

                  Rectangle {
                    anchors.fill: parent
                    visible: (mainInstance?.chapters?.length || 0) === 0 && !(mainInstance?.isLoadingChapters || false)
                    color: "transparent"

                    NText {
                      anchors.centerIn: parent
                      text: "No chapters loaded"
                      color: Color.mOnSurfaceVariant
                      pointSize: Style.fontSizeXS
                    }
                  }
                }
              }
            }
          }
        }

        // ===== Reader Area =====
        Rectangle {
          Layout.fillWidth: true
          Layout.fillHeight: true
          radius: Style.radiusM
          color: Qt.alpha(Color.mSurfaceVariant, 0.28)
          border.width: 1
          border.color: Qt.alpha(Style.capsuleBorderColor, 0.7)

          Item {
            anchors.fill: parent
            anchors.margins: Style.marginS

            // Empty State
            Rectangle {
              anchors.fill: parent
              visible: !mainInstance?.currentChapter
              color: "transparent"

              Column {
                anchors.centerIn: parent
                spacing: Style.marginS

                NIcon {
                  anchors.horizontalCenter: parent.horizontalCenter
                  icon: resolveControlIcon("book-2", "settings")
                  pointSize: Style.fontSizeXXL
                  color: Qt.alpha(Color.mOnSurfaceVariant, 0.3)
                }

                NText {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Select a chapter"
                  color: Color.mOnSurface
                  pointSize: Style.fontSizeM
                  font.weight: Font.Medium
                }

                NText {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Browse manga in the sidebar or search by title"
                  color: Color.mOnSurfaceVariant
                  pointSize: Style.fontSizeS
                }
              }
            }

            // Loading State
            Rectangle {
              anchors.centerIn: parent
              visible: mainInstance?.isLoadingPages || false
              width: loadingColumn.implicitWidth + Style.marginL * 2
              height: loadingColumn.implicitHeight + Style.marginL * 2
              radius: Style.radiusM
              color: Qt.alpha(Color.mSurface, 0.9)
              border.width: 1
              border.color: Qt.alpha(Style.capsuleBorderColor, 0.7)

              Column {
                id: loadingColumn
                anchors.centerIn: parent
                spacing: Style.marginS

                NIcon {
                  anchors.horizontalCenter: parent.horizontalCenter
                  icon: resolveControlIcon("loader-2", "settings")
                  pointSize: Style.fontSizeL
                  color: Color.mPrimary

                  RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                    running: parent.parent.visible
                  }
                }

                NText {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Loading pages..."
                  color: Color.mOnSurface
                  pointSize: Style.fontSizeS
                }
              }
            }

             // Reader Scroll
             ScrollView {
               id: readerScroll
               anchors.top: parent.top
               anchors.left: parent.left
               anchors.right: parent.right
               anchors.bottom: chapterNavigation.visible ? chapterNavigation.top : parent.bottom
               visible: mainInstance?.currentChapter ? true : false
               clip: true

               onVisibleChanged: {
                 if (visible) {
                   if (mainInstance?.bumpReaderRenderEpoch) {
                     mainInstance.bumpReaderRenderEpoch("panel_open", false);
                   }
                   Qt.callLater(updateVisiblePages);
                   scheduleAnchorRestore("reader_visible", 150);
                 }
               }

               onWidthChanged: {
                 if (mainInstance?.bumpReaderRenderEpoch) {
                   mainInstance.bumpReaderRenderEpoch("reader_width_changed", false);
                 }
                 Qt.callLater(updateVisiblePages);
                 scheduleAnchorRestore("reader_width_changed", 120);
               }

               onHeightChanged: {
                 if (mainInstance?.bumpReaderRenderEpoch) {
                   mainInstance.bumpReaderRenderEpoch("reader_height_changed", false);
                 }
                 Qt.callLater(updateVisiblePages);
                 scheduleAnchorRestore("reader_height_changed", 120);
               }

               Connections {
                 target: readerScroll.contentItem
                 enabled: target !== null

                 function onContentYChanged() {
                   updateVisiblePages();
                   captureReaderAnchor("scroll", false);
                 }
               }

               Column {
                 id: pageColumn
                 width: Math.max(220, readerScroll.width - Style.marginM * 2)
                 spacing: Style.marginS

                 Repeater {
                   id: pageRepeater
                   model: mainInstance?.pageUrls || []

                   delegate: Item {
                     id: pageItem
                     required property var modelData
                     required property int index
                     property string originalSource: String(modelData.source || "")
                     property string imageSource: originalSource
                     property bool uploadsFallbackTried: false
                     property bool inViewport: false
                     property int renderEpoch: mainInstance?.readerRenderEpoch ?? 0
                     property int cacheRevision: mainInstance?.pageImageCacheRevision ?? 0
                     property int slotRevision: mainInstance?.pageSlotRevision ?? 0
                     property var slotState: {
                       var revisionToken = slotRevision;
                       if (revisionToken < 0) {
                         return ({ status: "loading", retryCount: 0, failureCount: 0, lastError: "", updatedAtMs: 0 });
                       }
                       return mainInstance?.getPageSlotState
                           ? mainInstance.getPageSlotState(modelData, index)
                           : ({ status: "loading", retryCount: 0, failureCount: 0, lastError: "", updatedAtMs: 0 });
                     }
                     property string slotStatus: String(slotState.status || "loading")
                     property bool slotRecoverable: slotStatus === "error" || slotStatus === "stale"
                     property int slotRetryCount: Number(slotState.retryCount || slotState.failureCount || 0)
                     property int slotUpdatedAtMs: Number(slotState.updatedAtMs || 0)
                     property int slotClockMs: Date.now()
                     property bool slotLoadingStalled: slotStatus === "loading"
                         && imageSource !== ""
                         && (inViewport || keepLoaded)
                       && Math.max(0, slotClockMs - slotUpdatedAtMs) >= Number(mainInstance?.readerTransitionStuckThresholdMs || 2500)
                     property bool slotForceFetchVisible: slotRecoverable || slotLoadingStalled
                     property bool slotRefetchPending: mainInstance?.isPageRefetchPending
                         ? mainInstance.isPageRefetchPending(modelData, index)
                         : !!mainInstance?.chapterRecoveryInProgress
                     property bool showChangeQualityAction: slotForceFetchVisible && slotRetryCount > 1
                     property bool keepLoaded: {
                       var revisionToken = cacheRevision;
                       if (revisionToken < 0) {
                         return false;
                       }
                       return mainInstance ? mainInstance.isPageCached(modelData, index) : false;
                     }
                     readonly property real imageMargin: 2
                     readonly property real resolvedImageWidth: Math.max(120, pageColumn.width - imageMargin * 2)
                     readonly property real resolvedImageRatio: (pageImage.status === Image.Ready
                             && pageImage.implicitWidth > 0
                             && pageImage.implicitHeight > 0)
                         ? (pageImage.implicitHeight / pageImage.implicitWidth)
                         : 1.45
                     readonly property real resolvedImageHeight: Math.max(120, resolvedImageWidth * resolvedImageRatio)
                     readonly property int imageStatus: pageImage.status

                     width: pageColumn.width
                     height: resolvedImageHeight + imageMargin * 2

                     Timer {
                       interval: 1000
                       running: true
                       repeat: true
                       onTriggered: pageItem.slotClockMs = Date.now()
                     }

                     onRenderEpochChanged: {
                       var remountReason = String(mainInstance?.lastReaderRecoveryReason || "");
                       if (!ReaderRecovery.shouldResetSourceForReason(remountReason)) {
                         return;
                       }

                       if (mainInstance?.markPageSlotLoading) {
                         mainInstance.markPageSlotLoading(modelData, index, "render-epoch-remount");
                       }

                       if (pageItem.inViewport || pageItem.keepLoaded) {
                         var reboundSource = pageItem.imageSource;
                         pageItem.imageSource = "";
                         Qt.callLater(function() {
                           pageItem.imageSource = reboundSource;
                         });
                       }
                     }

                     Rectangle {
                       anchors.fill: parent
                       radius: Style.radiusS
                       color: Qt.alpha(Color.mSurface, 0.3)
                     }

                     onInViewportChanged: {
                       if (inViewport) {
                         if (mainInstance && mainInstance.touchPageCacheEntry) {
                           mainInstance.touchPageCacheEntry(modelData, index);
                         }
                         Diagnostics.debug("reader.viewport.enter", {
                           chapterId: mainInstance?.currentChapter?.id || "",
                           pageIndex: index,
                           source: originalSource
                         }, "Page entered viewport activation window");
                       }
                     }

                     Image {
                       id: pageImage
                       x: pageItem.imageMargin
                       y: pageItem.imageMargin
                       width: pageItem.resolvedImageWidth
                       height: pageItem.resolvedImageHeight
                       source: (pageItem.inViewport || pageItem.keepLoaded) ? pageItem.imageSource : ""
                       asynchronous: true
                       cache: true
                       fillMode: Image.PreserveAspectFit
                       opacity: status === Image.Ready ? 1.0 : 0.0

                        onSourceChanged: {
                          if (mainInstance?.markPageSlotLoading && source !== "") {
                            mainInstance.markPageSlotLoading(modelData, pageItem.index, "source_changed");
                          }
                        }

                       Behavior on opacity {
                         NumberAnimation { duration: 200 }
                       }

                       onStatusChanged: {
                         if (!mainInstance) { return; }

                          if (status === Image.Loading) {
                            if (mainInstance.markPageSlotLoading) {
                              mainInstance.markPageSlotLoading(modelData, pageItem.index, "image_loading");
                            }
                            return;
                          }

                         if (status === Image.Ready) {
                           if (mainInstance.registerPageImageReady) {
                             mainInstance.registerPageImageReady(modelData, pageImage.implicitWidth, pageImage.implicitHeight, pageItem.index);
                           }
                           if (mainInstance.markPageSlotReady) {
                             mainInstance.markPageSlotReady(modelData, pageItem.index, pageItem.imageSource);
                           }
                           return;
                         }

                         if (status !== Image.Error) {
                           return;
                         }

                         if (!pageItem.uploadsFallbackTried) {
                           var uploadsFallbackUrl = mainInstance.toUploadsFallbackUrl(pageItem.imageSource);
                           if (uploadsFallbackUrl && uploadsFallbackUrl !== "") {
                             Diagnostics.warn("reader.image.fallback_uploads", {
                               chapterId: mainInstance?.currentChapter?.id || "",
                               pageIndex: pageItem.index,
                               source: pageItem.imageSource,
                               fallback: uploadsFallbackUrl
                             }, "Image failed from At-Home host, trying uploads fallback");
                             if (mainInstance.markPageSlotStale) {
                               mainInstance.markPageSlotStale(modelData, pageItem.index, "at-home-host-error", pageItem.imageSource);
                             }
                             if (mainInstance.invalidatePageCacheEntry) {
                               mainInstance.invalidatePageCacheEntry(modelData, pageItem.imageSource, "at-home-host-error", pageItem.index);
                             }
                             pageItem.uploadsFallbackTried = true;
                             pageItem.imageSource = uploadsFallbackUrl;
                             return;
                           }
                         }

                         if (pageItem.uploadsFallbackTried && pageItem.imageSource !== pageItem.originalSource) {
                           pageItem.imageSource = pageItem.originalSource;
                         }

                         if (status === Image.Error) {
                           Diagnostics.warn("reader.image.error", {
                             chapterId: mainInstance?.currentChapter?.id || "",
                             pageIndex: pageItem.index,
                             source: pageItem.originalSource,
                             fallbackTried: pageItem.uploadsFallbackTried
                           }, "Image delegate reported load failure");
                           if (mainInstance.markPageSlotError) {
                             mainInstance.markPageSlotError(modelData, pageItem.index, "image-error", pageItem.originalSource);
                           }
                           if (mainInstance.invalidatePageCacheEntry) {
                             mainInstance.invalidatePageCacheEntry(modelData, pageItem.originalSource, "image-error", pageItem.index);
                           }
                           mainInstance.handleChapterImageFailure(pageItem.originalSource);
                         }
                       }
                     }

                     Rectangle {
                       anchors.fill: pageImage
                       radius: Style.radiusS
                       visible: pageImage.source !== "" && pageImage.status !== Image.Ready && !pageItem.slotRecoverable
                       color: Qt.alpha(Color.mSurface, 0.42)

                       ColumnLayout {
                         anchors.centerIn: parent
                         spacing: Style.marginS

                         NText {
                           Layout.alignment: Qt.AlignHCenter
                           text: pageItem.slotLoadingStalled ? "Loading is taking longer than expected" : "Loading page..."
                           pointSize: Style.fontSizeXS
                           color: Color.mOnSurfaceVariant
                           horizontalAlignment: Text.AlignHCenter
                         }

                         Components.PageRefetchAction {
                           Layout.alignment: Qt.AlignHCenter
                           visibleAction: pageItem.slotLoadingStalled
                           actionIcon: resolveControlIcon("refresh", "settings")
                           actionLabel: "Force Fetch"
                           actionEnabled: !pageItem.slotRefetchPending
                           busy: pageItem.slotRefetchPending
                           onTriggered: {
                             if (mainInstance?.requestPageRefetch) {
                               mainInstance.requestPageRefetch(modelData, pageItem.index, "manual_refetch");
                             }
                           }
                         }
                       }
                     }

                     Rectangle {
                       anchors.fill: pageImage
                       radius: Style.radiusS
                       visible: pageItem.slotRecoverable
                       color: Qt.rgba(0.937, 0.267, 0.267, 0.14)
                       border.width: 1
                       border.color: Qt.rgba(0.937, 0.267, 0.267, 0.35)

                       ColumnLayout {
                         anchors.centerIn: parent
                         spacing: Style.marginS

                         NText {
                           Layout.alignment: Qt.AlignHCenter
                           text: pageItem.slotStatus === "stale" ? "Refreshing page source" : "Page failed to render"
                           pointSize: Style.fontSizeXS
                           color: "#ef4444"
                         }

                         NText {
                           Layout.alignment: Qt.AlignHCenter
                           visible: String(pageItem.slotState.lastError || "") !== ""
                           text: String(pageItem.slotState.lastError || "")
                           pointSize: Style.fontSizeXS - 1
                           color: Qt.alpha(Color.mOnSurfaceVariant, 0.9)
                           horizontalAlignment: Text.AlignHCenter
                         }

                         Components.PageRefetchAction {
                           Layout.alignment: Qt.AlignHCenter
                           visibleAction: pageItem.slotForceFetchVisible
                           actionIcon: resolveControlIcon("refresh", "settings")
                           actionLabel: "Force Fetch"
                           actionEnabled: !pageItem.slotRefetchPending
                           busy: pageItem.slotRefetchPending
                           onTriggered: {
                             if (mainInstance?.requestPageRefetch) {
                               mainInstance.requestPageRefetch(modelData, pageItem.index, "manual_refetch");
                             }
                           }
                         }

                         Components.PageRefetchAction {
                           Layout.alignment: Qt.AlignHCenter
                           visibleAction: pageItem.showChangeQualityAction
                           actionIcon: mainInstance?.qualityMode === "data"
                               ? resolveControlIcon("photo-down", "image")
                               : resolveControlIcon("photo-up", "image")
                           actionLabel: mainInstance?.qualityMode === "data"
                               ? "Change Quality (Data Saver)"
                               : "Change Quality (High)"
                           actionEnabled: !pageItem.slotRefetchPending
                           busy: pageItem.slotRefetchPending
                           onTriggered: {
                             if (mainInstance?.requestPageRefetchWithQualityToggle) {
                               mainInstance.requestPageRefetchWithQualityToggle(modelData, pageItem.index, "manual_quality_refetch");
                             }
                           }
                         }
                       }
                     }
                   }
                 }
               }
             }

            // Scroll to Top Button
            Rectangle {
              id: scrollToTopBtn
              anchors.right: parent.right
              anchors.bottom: chapterNavigation.visible ? chapterNavigation.top : parent.bottom
              anchors.rightMargin: Style.marginM
              anchors.bottomMargin: Style.marginM
              width: 36
              height: 36
              radius: width / 2
              color: Qt.alpha(Color.mSurface, 0.9)
              border.width: 1
              border.color: Qt.alpha(Style.capsuleBorderColor, 0.5)
              visible: readerScroll.visible && readerScroll.contentItem.contentY > readerScroll.height * 0.5
              opacity: visible ? 1.0 : 0.0

              Behavior on opacity {
                NumberAnimation { duration: 150 }
              }

              NIcon {
                anchors.centerIn: parent
                icon: resolveControlIcon("chevron-up", "chevron-right")
                pointSize: Style.fontSizeS
                color: Color.mOnSurface
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  readerScroll.contentItem.contentY = 0;
                }
              }
            }

             // Bottom Chapter Navigation
             Rectangle {
               id: chapterNavigation
               anchors.left: parent.left
               anchors.right: parent.right
               anchors.bottom: parent.bottom
               height: 46
               visible: mainInstance?.currentChapter ? true : false
               radius: Style.radiusS
               color: Qt.alpha(Color.mSurface, 0.9)
               border.width: 1
               border.color: Qt.alpha(Style.capsuleBorderColor, 0.65)

               RowLayout {
                 anchors.fill: parent
                 anchors.leftMargin: Style.marginS
                 anchors.rightMargin: Style.marginS
                 spacing: Style.marginS

                 NIconButton {
                   icon: resolveControlIcon("chevron-left", "settings")
                   tooltipText: "Previous chapter"
                   enabled: mainInstance?.currentChapter ? true : false
                   onClicked: {
                     if (mainInstance) { mainInstance.openPreviousChapter(); }
                   }
                 }

                 NIconButton {
                   icon: resolveControlIcon("check", "settings")
                   tooltipText: "Mark chapter read"
                   enabled: mainInstance?.currentChapter ? true : false
                   onClicked: {
                     if (mainInstance) { mainInstance.markCurrentChapterRead(); }
                   }
                 }

                 NText {
                   Layout.fillWidth: true
                   text: mainInstance?.currentChapter
                       ? mainInstance.chapterLabel(mainInstance.currentChapter)
                       : "No chapter selected"
                   color: Color.mOnSurface
                   pointSize: Style.fontSizeXS
                   elide: Text.ElideRight
                   horizontalAlignment: Text.AlignHCenter
                 }

                 NIconButton {
                   icon: resolveControlIcon("chevron-right", "settings")
                   tooltipText: "Next chapter"
                   enabled: mainInstance?.currentChapter ? true : false
                   onClicked: {
                     if (mainInstance) { mainInstance.openNextChapter(); }
                   }
                 }
               }
             }
           }
         }
       }
     }
   }

   function recoverVisibleLoadingPages(reason) {
     if (!readerScroll || !readerScroll.visible || !pageRepeater || !mainInstance || !mainInstance.requestTransitionSettledPageRecovery) {
       return 0;
     }

     var inspectedCount = 0;
     var recoveredCount = 0;
     var thresholdMs = Number(mainInstance?.readerTransitionStuckThresholdMs || 2500);

     for (var i = 0; i < pageRepeater.count; i++) {
       var item = pageRepeater.itemAt(i);
       if (!item || !item.inViewport) {
         continue;
       }

       inspectedCount++;
       var ageMs = Math.max(0, Number(item.slotClockMs || Date.now()) - Number(item.slotUpdatedAtMs || 0));
       var shouldRecover = item.slotStatus === "loading"
           && item.imageSource !== ""
           && !item.slotRefetchPending
           && item.imageStatus !== Image.Ready
           && ageMs >= thresholdMs;
       if (!shouldRecover) {
         continue;
       }

       var started = mainInstance.requestTransitionSettledPageRecovery(
         item.modelData,
         item.index,
         reason || "transition_settle_recovery",
         item.slotUpdatedAtMs);
       if (started) {
         recoveredCount++;
       }
     }

     if (recoveredCount > 0) {
       Diagnostics.warn("reader.transition.reconcile.recovery", {
         chapterId: mainInstance?.currentChapter?.id || "",
         inspectedCount: inspectedCount,
         recoveredCount: recoveredCount,
         thresholdMs: thresholdMs,
         reason: String(reason || "transition_settle_recovery")
       }, "Requested targeted recovery for visible pages stuck loading after transition settle");
     }

     return recoveredCount;
   }

   // Function to update which pages are visible based on scroll position
   function updateVisiblePages() {
     if (!readerScroll || !readerScroll.contentItem || !pageRepeater || !mainInstance) {
       return;
     }

     var viewportTop = readerScroll.contentItem.contentY;
     var viewportBottom = viewportTop + readerScroll.height;
     var buffer = 220;
     var activatedCount = 0;
     var totalCount = 0;

     for (var i = 0; i < pageRepeater.count; i++) {
       var item = pageRepeater.itemAt(i);
       if (!item) {
         continue;
       }

       totalCount++;
       var itemTop = item.y;
       var itemBottom = itemTop + item.height;
       var nextVisible = !(itemBottom < viewportTop - buffer || itemTop > viewportBottom + buffer);
       item.inViewport = nextVisible;
       if (nextVisible) {
         activatedCount++;
       }
     }

     Diagnostics.debug("reader.viewport.update", {
       chapterId: mainInstance?.currentChapter?.id || "",
       activatedCount: activatedCount,
       totalCount: totalCount,
       viewportTop: Math.round(viewportTop),
       viewportBottom: Math.round(viewportBottom)
     }, "Updated viewport-based page activation");
   }
}