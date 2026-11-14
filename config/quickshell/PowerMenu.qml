// Session / power menu on SUPER+Escape.
//
// Five black cards in a row, each headed by its number in kanji. The chosen
// one is reversed to a pale block with its numeral in red.
// Left/Right (or Up/Down) or 1-5 to move, Enter to run, Esc to close.
import QtQuick
import Quickshell

PanelWindow {
    id: win

    property var  th
    property bool shown: false
    // Injected by shell.qml so command execution stays in one place.
    property var  exec

    readonly property int cardW: 168
    readonly property int cardH: 196
    readonly property int gap: 12

    property int sel: 0

    // Which locker to use. Set from settings so the new lock screen can be
    // adopted (or backed out of) without editing this file.
    property string lockCmd: "setsid hyprlock -q >/dev/null 2>&1 </dev/null &"

    readonly property var actions: [
        { name: "Lock",      mark: "一", note: "Locks the screen now",                        danger: false,
          cmd:  win.lockCmd },
        { name: "Suspend",   mark: "二", note: "Sleeps, ignoring apps that block it",         danger: false,
          cmd:  "systemctl suspend -i || loginctl suspend -i" },
        { name: "Log out",   mark: "三", note: "Ends the session, back to the login screen",  danger: false,
          cmd:  "hyprctl dispatch exit || loginctl terminate-user \"$USER\"" },
        { name: "Restart",   mark: "四", note: "Reboots the machine",                         danger: true,
          cmd:  "systemctl reboot" },
        { name: "Shut down", mark: "五", note: "Powers the machine off",                      danger: true,
          cmd:  "systemctl poweroff" }
    ]

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    focusable: true
    visible: shown

    function open()  { sel = 0; shown = true }
    function close() { shown = false }

    onShownChanged: if (shown) keys.forceActiveFocus()

    function move(d) {
        var n = actions.length
        sel = (sel + d + n) % n
    }

    function run() {
        var a = actions[sel]
        if (!a) return
        close()
        if (win.exec) win.exec(a.cmd)
    }

    Rectangle {
        anchors.fill: parent
        color: win.th.scrim
        opacity: win.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: win.th.tPanel; easing.type: Easing.OutQuint } }
        MouseArea { anchors.fill: parent; onClicked: win.close() }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: win.shown
        Keys.onPressed: function (e) {
            if (e.key === Qt.Key_Escape) { win.close(); e.accepted = true }
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down || e.key === Qt.Key_Tab) { win.move(1); e.accepted = true }
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_Up) { win.move(-1); e.accepted = true }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { win.run(); e.accepted = true }
            // Digits select only. Running straight off a keypress would put
            // "shut down" one stray 5 away.
            else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_5) {
                win.sel = e.key - Qt.Key_1
                e.accepted = true
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 18
            opacity: win.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: win.th.tPanel; easing.type: Easing.OutQuint } }

            Row {
                spacing: win.gap

                Repeater {
                    model: win.actions
                    Rectangle {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property bool on: index === win.sel
                        width: win.cardW
                        height: win.cardH
                        radius: win.th.rLarge
                        color: on ? win.th.text : win.th.ink
                        border.width: 1
                        border.color: on ? win.th.text : win.th.outlineVariant
                        Behavior on color { ColorAnimation { duration: win.th.tSnap } }

                        Text {
                            x: 18; y: 14
                            text: card.modelData.mark
                            color: card.on ? win.th.primary : win.th.outlineVariant
                            font.family: win.th.body
                            font.pixelSize: win.th.fs(40)
                        }
                        Rectangle {
                            x: 18; y: 92
                            width: 14; height: 2
                            color: win.th.primary
                        }
                        Text {
                            x: 18; y: 106
                            width: parent.width - 36
                            text: card.modelData.name
                            color: card.on ? win.th.surface : win.th.text
                            font.family: win.th.display
                            font.pixelSize: win.th.fs(15)
                            font.weight: Font.Bold
                        }
                        Text {
                            x: 18; y: 134
                            width: parent.width - 36
                            text: card.modelData.note
                            color: card.on ? win.th.surfaceContainerHighest : win.th.outline
                            font.family: win.th.body
                            font.pixelSize: win.th.fs(10)
                            wrapMode: Text.WordWrap
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: win.sel = card.index
                            onClicked: { win.sel = card.index; win.run() }
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "← → choose   ↵ confirm   esc cancel"
                color: win.th.outline
                font.family: win.th.body
                font.pixelSize: win.th.fs(10)
            }
        }
    }
}
