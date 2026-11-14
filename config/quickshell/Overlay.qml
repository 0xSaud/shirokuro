// Shared chrome for the full-screen picker panels: scrim, card, header,
// Esc to close, click-outside to close. Keeps every picker looking identical
// without each one re-implementing the same shell.
//
// "Ink" look: a black lacquer card with a hairline frame. The header carries
// a short red stroke, the title in bold, and the kicker after it in grey.
import QtQuick
import Quickshell

PanelWindow {
    id: win

    property var    th
    property bool   shown: false
    property string eyebrow: ""
    property string title: ""
    property string hint: ""
    property color  tint: th ? th.primary : "#888888"
    property int    cardWidth: 780
    property int    cardHeight: 580

    default property alias content: body.data
    signal opened()
    signal keyPressed(var event)

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    focusable: true
    visible: shown

    function open()  { shown = true; opened() }
    function close() { shown = false }
    onShownChanged: if (shown) keyScope.forceActiveFocus()

    // Kickers arrive as "SETTINGS"; show them as "settings".
    function lower(s) { return ("" + s).toLowerCase() }

    Rectangle {
        anchors.fill: parent
        color: win.th.scrim
        opacity: win.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: win.th.tPanel; easing.type: Easing.OutQuint } }
        MouseArea { anchors.fill: parent; onClicked: win.close() }
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: win.shown
        Keys.onPressed: function (e) {
            if (e.key === Qt.Key_Escape) { win.close(); e.accepted = true; return }
            win.keyPressed(e)
        }

        Rectangle {
            id: card
            width: win.cardWidth
            height: win.cardHeight
            anchors.centerIn: parent
            radius: win.th.rLarge
            color: win.th.ink
            border.width: 1
            border.color: win.th.outlineVariant
            clip: true

            opacity: win.shown ? 1 : 0
            scale: win.shown ? 1 : 0.985
            Behavior on opacity { NumberAnimation { duration: win.th.tPanel; easing.type: Easing.OutQuint } }
            Behavior on scale   { NumberAnimation { duration: win.th.tPanel; easing.type: Easing.OutQuint } }

            // Swallow clicks so the scrim's close handler doesn't fire through the card.
            MouseArea { anchors.fill: parent }

            Item {
                id: header
                width: parent.width
                height: 62

                Rectangle {
                    x: win.th.pad + 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3; height: 18; radius: 1.5
                    color: win.th.primary
                }
                Row {
                    x: win.th.pad + 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    Text {
                        anchors.baseline: kicker.baseline
                        text: win.title
                        color: win.th.surfaceText
                        font.family: win.th.display
                        font.pixelSize: win.th.fs(16)
                        font.weight: Font.Bold
                        visible: text.length > 0
                    }
                    Text {
                        id: kicker
                        text: win.lower(win.eyebrow)
                        color: win.th.outline
                        font.family: win.th.body
                        font.pixelSize: win.th.fs(11)
                        visible: text.length > 0
                    }
                }
                Text {
                    anchors.right: closeBtn.left
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.hint
                    color: win.th.outline
                    font.family: win.th.body
                    font.pixelSize: win.th.fs(10)
                }
                Rectangle {
                    id: closeBtn
                    anchors.right: parent.right
                    anchors.rightMargin: win.th.pad
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28; radius: win.th.rSmall
                    color: closeMa.containsMouse ? win.th.surfaceText : win.th.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text { anchors.centerIn: parent; text: "✕"
                           color: closeMa.containsMouse ? win.th.surface : win.th.onSurfaceVariant
                           font.family: win.th.body; font.pixelSize: win.th.fs(12) }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor; onClicked: win.close() }
                }
            }

            Rectangle { x: 1; y: header.height; width: parent.width - 2; height: 1; color: win.th.outlineVariant }

            Item {
                id: body
                y: header.height + 1
                width: parent.width
                height: parent.height - header.height - 1
            }
        }
    }
}
