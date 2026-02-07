import QtQuick

Item {
    id: root

    property var pluginApi: null

    Component.onCompleted: {
        Logger.d("mangowc-keymode-submap", "Plugin main instance loaded");
    }
}
