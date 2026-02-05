import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

// plugin documentation https://docs.noctalia.dev/development/plugins/getting-started/
Item {
    id: root

    property var pluginApi: null

    IpcHandler {
        function toggle(domain: string) {
            if (!pluginApi) return;
            
            var searchQuery = domain ? ">rbw " + domain : ">rbw ";
            
            pluginApi.withCurrentScreen(function(screen) {
                var launcherPanel = PanelService.getPanel("launcherPanel", screen);
                if (!launcherPanel) {
                    Logger.e("RBW", "No launcherPanel available.");
                    return;
                }
                
                var searchText = launcherPanel.searchText || "";
                var isInRbwMode = searchText.startsWith(">rbw");
                
                if (!launcherPanel.isPanelOpen) {
                    launcherPanel.open();
                    launcherPanel.setSearchText(searchQuery);
                    Logger.i("RBW", "Opened launcher with: " + searchQuery);
                } else if (isInRbwMode) {
                    launcherPanel.close();
                    Logger.i("RBW", "Closed launcher");
                } else {
                    launcherPanel.setSearchText(searchQuery);
                    Logger.i("RBW", "Set search text to: " + searchQuery);
                }
            });
        }

        function open(domain: string) {
            if (!pluginApi) return;
            
            var searchQuery = domain ? ">rbw " + domain : ">rbw ";
            
            pluginApi.withCurrentScreen(function(screen) {
                var launcherPanel = PanelService.getPanel("launcherPanel", screen);
                if (launcherPanel) {
                    launcherPanel.open();
                    launcherPanel.setSearchText(searchQuery);
                    Logger.i("RBW", "Opened launcher with: " + searchQuery);
                }
            });
        }

        function lock() {
            // TODO: implement lock via IPC
            Logger.i("RBW", "Lock command called via IPC");
        }

        function unlock() {
            // TODO: implement unlock via IPC
            Logger.i("RBW", "Unlock command called via IPC");
        }

        target: "plugin:bitwarden-rbw-launcher"
    }
}
