import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons

Item {
    id: playerView

    property url streamUrl
    property var headers: ({})
    property var metadata: ({})
    property var pluginApi: null

    signal backRequested()

    // ── Internal State ───────────────────────────────────────────────────────
    property bool controlsVisible: true
    property bool isFullscreen: false
    readonly property var anime: pluginApi?.mainInstance || null
    readonly property var player: anime?.player || null
    readonly property var audio:  anime?.audio || null

    component PlayerActionButton: Button {
        id: playerButton

        property bool prominent: false

        hoverEnabled: true
        flat: true
        implicitHeight: 34
        implicitWidth: Math.max(40, contentItem.implicitWidth + 18)

        background: Rectangle {
            radius: height / 2
            color: playerButton.prominent
                ? (playerButton.down
                    ? Color.mPrimary
                    : (playerButton.hovered ? Color.mPrimary : Color.mPrimaryContainer))
                : (playerButton.down
                    ? Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.95)
                    : (playerButton.hovered
                        ? Qt.rgba(Color.mSurfaceVariant.r, Color.mSurfaceVariant.g, Color.mSurfaceVariant.b, 0.88)
                        : "transparent"))
            border.width: 1
            border.color: playerButton.prominent
                ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, playerButton.hovered ? 0.95 : 0.5)
                : Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, playerButton.hovered ? 0.35 : 0.0)
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }
        }

        contentItem: Text {
            text: playerButton.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font: playerButton.font
            color: playerButton.prominent
                ? (playerButton.hovered ? Color.mOnPrimary : Color.mOnPrimaryContainer)
                : (playerButton.hovered ? Color.mOnSurface : Color.mOnSurfaceVariant)
            opacity: playerButton.hovered || playerButton.prominent ? 1 : 0.9
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }
    }

    // ── Metadata binding fixes ───────────────────────────────────────────────
    readonly property string displayTitle: metadata?.title || "Unknown Anime"
    readonly property string displayEpisode: metadata?.episode || "?"

    // ── Lifecycle Management ─────────────────────────────────────────────────
    onStreamUrlChanged: {
        if (!player) return
        player.stop()
        player.source = ""
        if (streamUrl.toString() === "") return
        Qt.callLater(function() {
            player.source = playerView.streamUrl
            player.play()
        })
    }

    function cleanup() {
        if (player) {
            player.stop()
            player.source = ""
        }
    }

    // ── UI Layout ────────────────────────────────────────────────────────────
    Rectangle {
        id: playerContainer
        anchors.fill: parent
        color: Color.mSurface
        radius: Style.radiusL
        clip: true

        // ── Mouse Area for Controls ──────────────────────────────────────────
        MouseArea {
            id: globalMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: controlsVisible = !controlsVisible
            onPositionChanged: {
                controlsVisible = true
                hideTimer.restart()
            }
        }

        Timer {
            id: hideTimer
            interval: 3500
            onTriggered: if (player && player.playbackState === 1) controlsVisible = false
            running: true
        }

        // ── Loading Indicator ────────────────────────────────────────────────
        BusyIndicator {
            anchors.centerIn: parent
            running: player && (player.mediaStatus === 2 || player.mediaStatus === 4)
        }

        // ── Top Bar ──────────────────────────────────────────────────────────
        Rectangle {
            id: topBar
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 64
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.9) }
                GradientStop { position: 1.0; color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.0) }
            }
            opacity: controlsVisible ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 300 } }

            RowLayout {
                anchors { fill: parent; leftMargin: 20; rightMargin: 20 }
                spacing: 16
                
                PlayerActionButton {
                    text: "←"
                    onClicked: {
                        cleanup()
                        playerView.backRequested()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    Text {
                        text: playerView.displayTitle
                        color: Color.mOnSurface; font.pixelSize: 14; font.bold: true; elide: Text.ElideRight
                    }
                    Text {
                        text: "Episode " + playerView.displayEpisode
                        color: Color.mOnSurfaceVariant; font.pixelSize: 11
                    }
                }

                PlayerActionButton {
                    text: "MPV"
                    prominent: true
                    onClicked: {
                        if (anime) {
                            var t = playerView.displayTitle + " - Ep " + playerView.displayEpisode
                            anime.playWithMpv(playerView.streamUrl, playerView.headers.Referer || "", t, playerView.headers || ({}), "hls")
                            cleanup()
                            playerView.backRequested()
                        }
                    }
                }
            }
        }

        // ── Bottom Controls ──────────────────────────────────────────────────
        Rectangle {
            id: bottomBar
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 100
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(Color.mSurface.r, Color.mSurface.g, Color.mSurface.b, 0.9) }
            }
            opacity: controlsVisible ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 300 } }

            ColumnLayout {
                anchors { fill: parent; leftMargin: 20; rightMargin: 20; bottomMargin: 10 }
                spacing: 8
                
                // Seek Bar
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: formatTime(player ? player.position : 0)
                        color: Color.mOnSurface; font.pixelSize: 12; font.family: "Monospace"
                    }

                    Slider {
                        id: seekSlider
                        Layout.fillWidth: true
                        from: 0
                        to: player ? Math.max(player.duration, 1) : 1
                        value: player ? player.position : 0
                        onMoved: if (player) player.position = value
                    }

                    Text {
                        text: formatTime(player ? player.duration : 0)
                        color: Color.mOnSurface; font.pixelSize: 12; font.family: "Monospace"
                    }
                }

                // Buttons Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 24
                    
                    PlayerActionButton {
                        text: player && player.playbackState === 1 ? "⏸" : "▶"
                        font.pixelSize: 20
                        onClicked: {
                            if (!player) return
                            if (player.playbackState === 1)
                                player.pause()
                            else
                                player.play()
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }

    function formatTime(ms) {
        if (!ms || ms < 0) return "0:00"
        var totalSeconds = Math.floor(ms / 1000)
        var minutes = Math.floor(totalSeconds / 60)
        var seconds = totalSeconds % 60
        return minutes + ":" + (seconds < 10 ? "0" + seconds : seconds)
    }

    Component.onCompleted: {
        if (player && streamUrl.toString() !== "" && player.source.toString() !== streamUrl.toString()) {
            player.source = streamUrl
            player.play()
        }
    }
}
