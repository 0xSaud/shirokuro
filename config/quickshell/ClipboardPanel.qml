// Clipboard history, replacing the rofi menu on CTRL+B.
//
// Keeps the behaviour of the script it replaces: picking an entry puts it on the
// clipboard AND pastes it into the window you were in, using Ctrl+Shift+V for
// terminals and Ctrl+V everywhere else.
import QtQuick
import Quickshell
import Quickshell.Io

Overlay {
    id: win

    // Captured by the shell before this panel takes focus.
    property string pasteAddr: ""
    property string pasteClass: ""

    property var entries: []       // [{id, preview}]
    property string query: ""
    property int sel: 0
    property bool confirmWipe: false

    eyebrow: "CLIPBOARD"
    title: "History"
    hint: "↑↓ move   ↵ paste   esc close"
    cardWidth: 760
    cardHeight: 560

    onOpened: { query = ""; sel = 0; confirmWipe = false; lister.running = true }
    onKeyPressed: function (e) {
        if (e.key === Qt.Key_Down)      { win.move(1);  e.accepted = true }
        else if (e.key === Qt.Key_Up)   { win.move(-1); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { win.paste(); e.accepted = true }
    }

    Process {
        id: lister
        command: ["bash", "-c", "cliphist list 2>/dev/null || true"]
        stdout: StdioCollector {
            id: lsOut
            onStreamFinished: {
                var out = []
                var lines = ("" + lsOut.text).split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var l = lines[i]
                    if (l.length === 0) continue
                    var t = l.indexOf("\t")
                    if (t <= 0) continue
                    out.push({ id: l.substring(0, t), preview: l.substring(t + 1) })
                }
                win.entries = out
                win.sel = 0
            }
        }
    }

    readonly property var filtered: {
        var q = ("" + win.query).trim().toLowerCase()
        if (q.length === 0) return win.entries
        var out = []
        for (var i = 0; i < win.entries.length; i++)
            if (win.entries[i].preview.toLowerCase().indexOf(q) >= 0) out.push(win.entries[i])
        return out
    }
    onQueryChanged: sel = 0

    function move(d) {
        var n = filtered.length
        if (n === 0) return
        sel = (sel + d + n) % n
        list.positionViewAtIndex(sel, ListView.Contain)
    }

    // Terminals want Ctrl+Shift+V; everything else Ctrl+V.
    function isTerminal(cls) {
        return /kitty|scratch-term|alacritty|foot|wezterm|ghostty|konsole|terminator|tilix|xterm|urxvt|st-256color/i
               .test("" + cls)
    }

    function paste() {
        var e = filtered[sel]
        if (!e) return
        win.close()
        var addr = ("" + win.pasteAddr).trim()
        if (addr.length > 0 && addr.indexOf("0x") !== 0) addr = "0x" + addr
        var mods = isTerminal(win.pasteClass) ? "CTRL SHIFT" : "CTRL"
        var cmd = "cliphist decode " + e.id + " | wl-copy"
        if (addr.length > 0) {
            // Small pause so the clipboard is served and focus has settled.
            cmd += " && sleep 0.12 && hyprctl dispatch sendshortcut " +
                   "'" + mods + ", V, address:" + addr + "'"
        }
        Quickshell.execDetached(["bash", "-c", cmd])
    }

    // Delete one entry. The id is matched back against `cliphist list` rather
    // than reconstructing the record, so arbitrary clipboard content never has
    // to survive shell quoting.
    function removeOne(id) {
        Quickshell.execDetached(["bash", "-c",
            "cliphist list | awk -F'\\t' -v id=" + id + " '$1==id' | cliphist delete"])
        refreshTimer.restart()
    }

    Timer {
        id: refreshTimer
        interval: 180
        onTriggered: lister.running = true
    }

    function wipe() {
        Quickshell.execDetached(["bash", "-c",
            "cliphist wipe && notify-send -a Clipboard 'Clipboard' 'History cleared'"])
        win.close()
    }

    Item {
        anchors.fill: parent

        Item {
            id: searchBar
            width: parent.width
            height: 50
            TextInput {
                id: input
                x: win.th.pad
                width: parent.width - x - 130
                anchors.verticalCenter: parent.verticalCenter
                text: win.query
                onTextChanged: win.query = text
                color: win.th.surfaceText
                font.family: win.th.body; font.pixelSize: win.th.fs(15)
                clip: true
                focus: win.shown
                Component.onCompleted: forceActiveFocus()
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text.length === 0
                    text: "Search what you copied"
                    color: win.th.onSurfaceVariant
                    font.family: win.th.body; font.pixelSize: win.th.fs(15)
                }
                Keys.onPressed: function (e) {
                    if (e.key === Qt.Key_Escape) { win.close(); e.accepted = true }
                    else if (e.key === Qt.Key_Down) { win.move(1); e.accepted = true }
                    else if (e.key === Qt.Key_Up) { win.move(-1); e.accepted = true }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { win.paste(); e.accepted = true }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: wipeBtn.left
                anchors.rightMargin: 10
                text: win.filtered.length
                color: win.th.onSurfaceVariant
                font.family: win.th.mono; font.pixelSize: win.th.fs(11)
            }
            Rectangle {
                id: wipeBtn
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: win.th.pad
                width: win.confirmWipe ? 104 : 74
                Behavior on width { NumberAnimation { duration: win.th.tSnap } }
                height: 28
                radius: win.th.rSmall
                color: win.confirmWipe ? win.th.error
                                       : (wipeMa.containsMouse ? win.th.errorContainer : win.th.surfaceContainerHigh)
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: win.confirmWipe ? "Really clear?" : "Clear all"
                    color: win.confirmWipe ? win.th.errorText
                                           : (wipeMa.containsMouse ? win.th.errorContainerText : win.th.onSurfaceVariant)
                    font.family: win.th.body; font.pixelSize: win.th.fs(11)
                }
                MouseArea {
                    id: wipeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Two-step, so a stray click never destroys the history.
                    onClicked: { if (win.confirmWipe) win.wipe(); else win.confirmWipe = true }
                }
            }
        }
        Rectangle { y: searchBar.height; width: parent.width; height: 1; color: win.th.outlineVariant }

        Item {
            y: searchBar.height + 1
            width: parent.width
            height: parent.height - searchBar.height - 1

            Spine {
                x: win.th.pad - 4
                y: 8
                height: parent.height - 16
                ruleColor: win.th.outline
                tickColor: win.th.primary
                tickHeight: 22
                tickVisible: win.filtered.length > 0
                moveDuration: win.th.tSnap
                tickY: {
                    var it = list.currentItem
                    if (!it) return 0
                    return Math.max(0, it.y - list.contentY + (44 - 22) / 2 - 8)
                }
            }

            // The card is translucent, so on a busy wallpaper the desktop shows
            // straight through the list and lands behind the entry text. The list
            // gets its own near-solid well, so every row has the same quiet ground
            // whatever is behind the panel.
            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: win.th.pad + 7    // clears the spine
                anchors.rightMargin: win.th.pad - 8
                anchors.topMargin: 4
                anchors.bottomMargin: 4
                radius: win.th.r
                // Follows the opacity setting but never below a readable floor.
                color: Qt.rgba(win.th.surfaceContainerLow.r,
                               win.th.surfaceContainerLow.g,
                               win.th.surfaceContainerLow.b,
                               Math.max(0.93, win.th.panelOpacity))
            }

            ListView {
                id: list
                anchors.fill: parent
                anchors.leftMargin: win.th.pad + 14
                anchors.rightMargin: win.th.pad
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                clip: true
                model: win.filtered
                currentIndex: win.sel
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 44
                    radius: win.th.rSmall
                    color: index === win.sel ? win.th.surfaceContainerHighest : "transparent"
                    Behavior on color { ColorAnimation { duration: win.th.tSnap } }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 14
                        width: parent.width - 108
                        text: modelData.preview
                        color: win.th.surfaceText
                        font.family: win.th.body; font.pixelSize: win.th.fs(13)
                        elide: Text.ElideRight
                    }

                    // Remove just this entry. Only shown on the hovered row, so
                    // the list stays quiet.
                    Rectangle {
                        id: delBtn
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 42
                        width: 22; height: 22; radius: win.th.rSmall
                        // Fades with opacity, NOT `visible`. rowMa deliberately stops
                        // short of this button, so moving toward it used to flip
                        // visible=false — and an invisible item gets no mouse events,
                        // so delMa could never take over and the button hid itself
                        // out of reach. At opacity 0 it stays hit-testable.
                        opacity: (rowMa.containsMouse || delMa.containsMouse) ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 90 } }
                        color: delMa.containsMouse ? win.th.errorContainer : win.th.surfaceContainerHigh
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: delMa.containsMouse ? win.th.errorContainerText : win.th.onSurfaceVariant
                            font.family: win.th.body; font.pixelSize: win.th.fs(10)
                        }
                        MouseArea {
                            id: delMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.removeOne(modelData.id)
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        // Position in the list, NOT cliphist's internal id. The id
                        // climbs forever and survives a wipe, so it showed numbers
                        // in the thousands on an empty-looking history. This always
                        // starts at 1 and resets when you clear.
                        text: index + 1
                        color: win.th.onSurfaceVariant
                        font.family: win.th.mono; font.pixelSize: win.th.fs(9)
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        anchors.rightMargin: 66     // keep the delete button clickable
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: win.sel = index
                        onClicked: { win.sel = index; win.paste() }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: win.filtered.length === 0
                text: win.entries.length === 0 ? "Nothing copied yet" : "Nothing matches"
                color: win.th.onSurfaceVariant
                font.family: win.th.body; font.pixelSize: win.th.fs(13)
            }
        }
    }
}
