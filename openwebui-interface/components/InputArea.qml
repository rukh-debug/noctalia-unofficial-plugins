import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets

Rectangle {
    id: root
    
    property bool isGenerating: false
    
    signal messageSent(string text)
    signal stopRequested()
    
    implicitHeight: inputLayout.implicitHeight + (2 * Style.marginS)
    implicitWidth: inputLayout.implicitWidth + (2 * Style.marginS)

    color: Color.mSurface
    radius: Style.radiusM

    function focusInput() {
        if (inputField) inputField.forceActiveFocus();
    }

    RowLayout {
        id: inputLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.marginS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginS

        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Math.max(inputField.implicitHeight, 40), 100)

            TextArea {
                id: inputField
                placeholderText: "Type a message..."
                placeholderTextColor: Color.mOnSurfaceVariant
                color: Color.mOnSurface
                font.pointSize: Style.fontSizeM
                wrapMode: TextArea.Wrap
                background: null
                selectByMouse: true
                enabled: !root.isGenerating

                Keys.onReturnPressed: function (event) {
                    if (event.modifiers & Qt.ShiftModifier) {
                        inputField.insert(inputField.cursorPosition, "\n");
                    } else {
                        var text = inputField.text.trim();
                        if (text !== "") {
                            root.messageSent(text);
                            inputField.text = "";
                        }
                    }
                    event.accepted = true;
                }
            }
        }

        NIconButton {
            id: sendButton
            icon: root.isGenerating ? "player-stop" : "send"
            colorFg: root.isGenerating ? Color.mError : (inputField.text.trim() !== "" ? Color.mPrimary : Color.mOnSurfaceVariant)
            enabled: root.isGenerating || inputField.text.trim() !== ""
            tooltipText: root.isGenerating ? "Stop generation" : "Send"
            onClicked: {
                if (root.isGenerating) {
                    root.stopRequested();
                } else {
                    var text = inputField.text.trim();
                    if (text !== "") {
                        root.messageSent(text);
                        inputField.text = "";
                        inputField.forceActiveFocus();
                    }
                }
            }
        }
    }
}
