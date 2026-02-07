# Noctalia Plugins Development Guide

## Project Overview

This repository is an **unofficial plugin registry** for [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell), a Wayland compositor. Plugins are written in **QML/QtQuick** and extend Noctalia's functionality via launcher providers, bar widgets, and compositor integrations.

Official documentation: https://docs.noctalia.dev/development/plugins/getting-started/

## Architecture

### Plugin Structure
Each plugin is a self-contained directory in `~/.config/noctalia/plugins/` with:
- `manifest.json` - Plugin metadata and entry points (must match directory name in `id` field)
- `Main.qml` - Main plugin entry point (receives `pluginApi` property)
- Optional entry points:
  - `LauncherProvider.qml` - Launcher search provider (requires Noctalia 3.9.0+)
  - `BarWidget.qml` - Status bar widget
  - `DesktopWidget.qml` - Desktop widget
  - `ControlCenterWidget.qml` - Control center quick action
  - `Panel.qml` - Custom overlay panel
  - `Settings.qml` - Settings UI
  - `settings.json` - User-customizable settings (overrides `defaultSettings`)
- Optional: `i18n/*.json` - Translation files for internationalization

### Registry System
The `registry.json` file is **auto-generated** via GitHub Actions when `manifest.json` files change:
- Script: [.github/workflows/update-registry.js](.github/workflows/update-registry.js)
- Workflow: [.github/workflows/update-registry.yml](.github/workflows/update-registry.yml)
- **Never edit** `registry.json` manually - modify plugin manifests instead
- Registry includes: `id`, `name`, `version`, `author`, `description`, `repository`, `minNoctaliaVersion`, `license`, `tags`, `lastUpdated`
- Other manifest fields (`entryPoints`, `dependencies`, `metadata`) excluded for registry lightness

### Plugin API Injection
All QML components receive a `pluginApi` property from PluginService with:
- **Properties:**
  - `pluginId` - Unique plugin identifier (string, read-only)
  - `pluginDir` - Absolute path to plugin directory (string, read-only)
  - `pluginSettings` - User settings object (read/write, call `saveSettings()` after changes)
  - `manifest` - Full manifest with `metadata.defaultSettings` (read-only)
  - `currentLanguage` - Current UI language code (string, read-only)
  - `mainInstance` - Reference to Main.qml component (or null)
  - `panelOpenScreen` - Screen panel is displayed on (Panel.qml only)
- **Functions:**
  - `saveSettings()` - Persist settings to `~/.config/noctalia/plugins/<id>/settings.json`
  - `openPanel(screen, buttonItem?)` - Open plugin panel (pass widget reference for positioning)
  - `closePanel(screen)` - Close plugin panel
  - `togglePanel(screen, buttonItem?)` - Toggle panel open/closed
  - `withCurrentScreen(callback)` - Execute callback with current active screen (use in IPC handlers)
  - `tr(key, interpolations?)` - Translate text key (returns `## key ##` if missing)
  - `trp(key, count, defaultSingular?, defaultPlural?, interpolations?)` - Translate with plurals
  - `hasTranslation(key)` - Check if translation exists

## Key Conventions

### Manifest Entry Points
Map QML files to their purpose in `manifest.json` (all optional except `main`):
```json
"entryPoints": {
  "main": "Main.qml",           // Required - plugin initialization
  "launcherProvider": "LauncherProvider.qml",  // Launcher integration (3.9.0+)
  "barWidget": "BarWidget.qml",               // Bar widget
  "desktopWidget": "DesktopWidget.qml",       // Desktop widget
  "controlCenterWidget": "ControlCenterWidget.qml",  // Control center
  "panel": "Panel.qml",                       // Custom panel
  "settings": "Settings.qml"                  // Settings UI
}
```

### LauncherProvider Contract
**Required properties:**
- `property var pluginApi` - Injected by PluginService
- `property var launcher` - Back-reference to launcher panel (injected)
- `property string name` - Display name (e.g., "RBW")

**Required functions:**
- `function handleCommand(searchText)` - Return `true` if this provider handles the query
- `function commands()` - Return array of command objects for `>` menu
- `function getResults(searchText)` - Return array of result objects

**Optional properties:**
- `property bool handleSearch: false` - Participate in regular search (not just commands)
- `property string supportedLayouts: "both"` - "both", "list", or "grid"
- `property int preferredGridColumns: 5` - Grid columns
- `property bool supportsAutoPaste: false` - Enable auto-paste
- `property var categories: []` - Category IDs for browsing
- `property bool showsCategories: false` - Show category chips
- `property string selectedCategory: ""` - Current category
- `property string emptyBrowsingMessage: ""` - Message when empty

**Result object structure:**
```qml
{
  "name": "Result Title",
  "description": "Subtitle text",
  "icon": "star",
  "isTablerIcon": true,
  "displayString": "🎉",  // For emoji/text instead of icon
  "hideIcon": false,
  "singleLine": false,
  "autoPasteText": "🎉",
  "onActivate": function() { launcher.close() },
  "onAutoPaste": function() { /* track usage */ }
}
```

Example from [bitwarden-rbw-noctalia-launcher/LauncherProvider.qml](bitwarden-rbw-noctalia-launcher/LauncherProvider.qml#L14-L50):
```qml
property string name: "RBW"
function handleCommand(query) {
    return query.startsWith(">rbw");
}
function commands() {
    return [{ "name": ">rbw", "description": "Search passwords", 
              "icon": "key", "isTablerIcon": true,
              "onActivate": function() { launcher.setSearchText(">rbw ") } }]
}
```

### BarWidget Contract
**Required properties:**
- `property var pluginApi` - Injected by PluginService
- `property ShellScreen screen` - Current screen instance
- `property string widgetId` - Widget identifier
- `property string section` - Bar section (left/center/right)

**Per-screen properties (required for multi-monitor support):**
```qml
readonly property string screenName: screen?.name ?? ""
readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)
```

**Structure pattern (Item root with centered visualCapsule):**
```qml
Item {
    id: root
    readonly property real contentWidth: content.implicitWidth + Style.marginM * 2
    readonly property real contentHeight: capsuleHeight
    implicitWidth: contentWidth
    implicitHeight: contentHeight

    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
        radius: Style.radiusL
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth
        
        RowLayout {
            id: content
            anchors.centerIn: parent
            spacing: Style.marginS
        }
    }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
    }
}
```

**Settings access pattern (three-level fallback):**
```qml
readonly property int updateIntervalMs:
    pluginApi?.pluginSettings?.updateIntervalMs ??
    pluginApi?.manifest?.metadata?.defaultSettings?.updateIntervalMs ??
    200
```

### Settings Pattern
Define defaults in manifest's `metadata.defaultSettings`, override in `settings.json`:
```json
"metadata": {
  "defaultSettings": {
    "updateIntervalMs": 200,
    "textColor": "#f4d24f"
  }
}
```
Users customize via Settings UI or directly editing `~/.config/noctalia/plugins/<id>/settings.json`.

### IPC Integration
Plugins can expose IPC handlers for external control (see [bitwarden-rbw-noctalia-launcher/Main.qml](bitwarden-rbw-noctalia-launcher/Main.qml#L43-L99)):
```qml
IpcHandler {
    function toggle(domain: string) {
        if (!pluginApi) return;
        pluginApi.withCurrentScreen(function(screen) {
            var panel = PanelService.getPanel("launcherPanel", screen);
            if (panel) panel.toggle();
        });
    }
    target: "plugin:your-plugin-id"
}
```
Call via: `qs -c noctalia-shell ipc call plugin:your-plugin-id toggle "arg"`

### Context Menus (Bar Widgets)
**Always use `PanelService.showContextMenu()` for cross-compositor compatibility:**
```qml
NPopupContextMenu {
    id: contextMenu
    model: [
        { "label": "Refresh", "action": "refresh", "icon": "refresh" },
        { "label": "Settings", "action": "settings", "icon": "settings", "enabled": true }
    ]
    onTriggered: action => {
        contextMenu.close();
        PanelService.closeContextMenu(screen);
        if (action === "settings") {
            BarService.openPluginSettings(screen, pluginApi.manifest);
        }
    }
}

MouseArea {
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: (mouse) => {
        if (mouse.button === Qt.RightButton) {
            PanelService.showContextMenu(contextMenu, root, screen);
        }
    }
}
```

## Development Workflow

### Adding a New Plugin
1. Create directory: `my-plugin/` (or develop elsewhere and symlink to `~/.config/noctalia/plugins/`)
2. Create `manifest.json` with required fields:
   - `id` (must match directory name), `name`, `version`, `author`, `description`
   - `repository`, `minNoctaliaVersion`, `license`, `tags`
   - `entryPoints` with at least `"main": "Main.qml"`
3. Create `Main.qml` with `property var pluginApi`
4. Add other entry points as needed (BarWidget.qml, LauncherProvider.qml, etc.)
5. Push to `main` - registry auto-updates via GitHub Actions
6. No manual edits to `registry.json` needed

### Hot Reload (Development)
Enable hot reload to auto-reload plugins on file save:
```bash
# Start with debug mode
NOCTALIA_DEBUG=1 qs -c noctalia-shell

# Or via systemd
systemctl --user edit noctalia
# Add: Environment="NOCTALIA_DEBUG=1"
```
- QML files reload on save (state resets, settings persist)
- Translation files (`i18n/*.json`) reload without resetting state
- Watch terminal for QML errors during reload

### Testing Locally
1. Develop in `~/.config/noctalia/plugins/my-plugin/` or symlink from elsewhere
2. Restart Noctalia: `systemctl --user restart noctalia` or `killall qs && qs -p ~/.config/noctalia/noctalia-shell`
3. Open Settings → Plugins → Enable your plugin
4. For bar widgets: Settings → Bar → Add widget to section

### Installing from This Registry
Users add this registry via Noctalia Settings → Plugins → Sources → Add custom repository:
```
https://github.com/rukh-debug/noctalia-unofficial-plugins
```

### Debugging
**View logs:**
```bash
NOCTALIA_DEBUG=1 qs -c noctalia-shell
```

**Check status:**
```bash
cat ~/.config/noctalia/plugins.json  # Plugin list
cat ~/.config/noctalia/plugins/my-plugin/manifest.json
cat ~/.config/noctalia/plugins/my-plugin/settings.json
```

**Common issues:**
- Plugin not in settings → Verify valid JSON, ID matches directory, restart Noctalia
- Widget not in bar → Enable in Plugins tab, add in Bar tab
- Settings not persisting → Call `pluginApi.saveSettings()` after changes

### Common Imports
```qml
import QtQuick
import QtQuick.Layouts
import Quickshell          // Process, etc.
import Quickshell.Io       // FileView, File I/O
import qs.Commons          // Logger, Settings, Style, Color, I18n
import qs.Services.UI      // PanelService, ToastService, TooltipService, BarService
import qs.Services.System  // AudioService, BatteryService, NetworkService
import qs.Widgets          // NIcon, NText, NButton, NIconButton, NPopupContextMenu
```

### Noctalia Services & Styling
**Style constants (use per-screen versions in bar widgets):**
```qml
Style.capsuleHeight       // Bar height (use getCapsuleHeightForScreen(screenName))
Style.barFontSize         // Bar text size (use getBarFontSizeForScreen(screenName))
Style.marginS/M/L         // Spacing
Style.radiusS/M/L         // Corner radius
Style.capsuleColor        // Background
Style.capsuleBorderColor  // Outline
```

**Colors (theme-aware):**
```qml
Color.mSurface, Color.mSurfaceVariant       // Backgrounds
Color.mOnSurface, Color.mOnSurfaceVariant   // Text
Color.mPrimary                               // Accent
Color.mHover                                 // Hover state
```

**Services:**
```qml
Logger.i/d/w/e("ComponentName", "message", value)
ToastService.showNotice("Success") / showError("Failed")
TooltipService.show(item, "text", direction) / hide()
PanelService.openPanel/closePanel/isPanelOpen(panelId, screen)
PanelService.showContextMenu(menu, anchor, screen) / closeContextMenu(screen)
BarService.openPluginSettings(screen, manifest)
Settings.getBarPositionForScreen(screenName)  // "top", "bottom", "left", "right"
I18n.tr("common.key")  // Global translations (not plugin translations)
```

## Known Patterns

- **Process Execution**: Use `Quickshell.Io.Process` for external commands (see rbw lock/unlock in Main.qml)
- **Screen-Specific Bar Props**: Access via `Settings.getBarPositionForScreen(screenName)` and `Style.getCapsuleHeightForScreen(screenName)`
- **Launcher Panel Access**: `PanelService.getPanel("launcherPanel", screen)` with methods like `open()`, `setSearchText()`, `close()`
- **Panel Positioning**: Pass widget reference to `openPanel(screen, this)` to position panel near trigger
- **Hover Effects**: Use binding `color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor` instead of onEntered/onExited
- **Extended Click Areas**: Use Item root with centered Rectangle visualCapsule for better UX
- **Vertical Bar Support**: Check `isBarVertical` and swap width/height as needed
- **Category Browsing**: Implement `selectCategory()`, `getCategoryName()`, set `showsCategories: true`
- **Logging**: Use `Logger.i()`, `Logger.e()`, `Logger.d()` with component name as first arg
