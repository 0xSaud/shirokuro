// Window switcher. There was no Alt+Tab at all, so finding a window across
// 6 workspaces on 2 monitors meant remembering where you put it.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland

Overlay {
    id: win

    property var wins: []
    property string query: ""
    property int sel: 0

    eyebrow: "WINDOWS"
    title: "Switch to"
    hint: "↑↓ move   ↵ focus   esc close"
    cardWidth: 720
    cardHeight: 520

    onOpened: { query = ""; sel = 0; lister.running = true }

    Process {
        id: lister
        // hyprctl is authoritative and always present; no need to guess at a
        // toplevel model that may differ between Quickshell builds.
        command: ["bash", "-c",
            "hyprctl clients -j | jq -r '.[] | select(.mapped==true) | " +
            "[.address, (.workspace.id|tostring), .class, .title] | @tsv'"]
        stdout: StdioCollector {
            id: lsOut
            onStreamFinished: {
                var out = []
                var lines = ("" + lsOut.text).split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var f = lines[i].split("\t")
                    if (f.length < 4) continue
                    if (("" + f[0]).length === 0) continue
                    out.push({ addr: f[0], ws: f[1], cls: f[2], title: f[3] })
                }
                out.sort(function (a, b) {
                    var d = parseInt(a.ws) - parseInt(b.ws)
                    return d !== 0 ? d : a.cls.localeCompare(b.cls)
                })
                win.wins = out
                win.sel = 0
            }
        }
    }

    readonly property var filtered: {
        var q = ("" + win.query).trim().toLowerCase()
        if (q.length === 0) return win.wins
        var out = []
        for (var i = 0; i < win.wins.length; i++) {
            var w = win.wins[i]
            if (w.title.toLowerCase().indexOf(q) >= 0 || w.cls.toLowerCase().indexOf(q) >= 0)
                out.push(w)
        }
        return out
    }
    onQueryChanged: sel = 0

    function move(d) {
        var n = filtered.length
        if (n === 0) return
        sel = (sel + d + n) % n
        list.positionViewAtIndex(sel, ListView.Contain)
    }

    function focusIt() {
        var w = filtered[sel]
        if (!w) return
        win.close()
        Hyprland.dispatch("focuswindow address:" + w.addr)
    }

    Item {
        anchors.fill: parent

        Item {
            id: searchBar
            width: parent.width
            height: 48
            TextInput {
                id: input
                x: win.th.pad
                width: parent.width - x - 60
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
                    text: "Filter open windows"
                    color: win.th.onSurfaceVariant
                    font.family: win.th.body; font.pixelSize: win.th.fs(15)
                }
                Keys.onPressed: function (e) {
                    if (e.key === Qt.Key_Escape) { win.close(); e.accepted = true }
                    else if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab) { win.move(1); e.accepted = true }
                    else if (e.key === Qt.Key_Up) { win.move(-1); e.accepted = true }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { win.focusIt(); e.accepted = true }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: win.th.pad
                text: win.filtered.length
                color: win.th.onSurfaceVariant
                font.family: win.th.mono; font.pixelSize: win.th.fs(11)
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
                    return Math.max(0, it.y - list.contentY + (52 - 22) / 2 - 8)
                }
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
                    height: 52
                    radius: win.th.rSmall
                    color: index === win.sel ? win.th.surfaceContainerHighest : "transparent"
                    Behavior on color { ColorAnimation { duration: win.th.tSnap } }

                    IconImage {
                        id: ico
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 24
                        source: Quickshell.iconPath(modelData.cls.toLowerCase(), "application-x-executable")
                    }
                    Column {
                        anchors.left: ico.right
                        anchors.leftMargin: 14
                        anchors.right: wsChip.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            width: parent.width
                            text: modelData.title
                            color: win.th.surfaceText
                            font.family: win.th.body; font.pixelSize: win.th.fs(13)
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: modelData.cls
                            color: win.th.onSurfaceVariant
                            font.family: win.th.mono; font.pixelSize: win.th.fs(9)
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        id: wsChip
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26; height: 20; radius: win.th.rPill
                        color: win.th.surfaceContainer
                        Text {
                            anchors.centerIn: parent
                            text: modelData.ws
                            color: win.th.onSurfaceVariant
                            font.family: win.th.mono; font.pixelSize: win.th.fs(10)
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: win.sel = index
                        onClicked: { win.sel = index; win.focusIt() }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: win.filtered.length === 0
                text: win.wins.length === 0 ? "No open windows" : "Nothing matches"
                color: win.th.onSurfaceVariant
                font.family: win.th.body; font.pixelSize: win.th.fs(13)
            }
        }
    }
}
