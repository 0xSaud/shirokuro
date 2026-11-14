// App launcher on ALT+Space.
//
// A band of black lacquer that drops from under the bar across the full width
// of the screen. The query is typed beside the seal; results run left to
// right as tiles, and the chosen one is reversed to a pale block.
// Type to filter, Left/Right (or Up/Down, Tab) to move, Enter to open, Esc to close.
import QtQuick
import Quickshell
import Quickshell.Widgets

PanelWindow {
    id: win

    property var  th
    property bool shown: false

    readonly property int bandHeight: 214
    readonly property int tileW: 128

    property string query: ""
    property int    sel: 0

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusiveZone: 0
    focusable: true
    visible: shown || drop.running

    function open()  { query = ""; sel = 0; shown = true }
    function close() { shown = false }

    onShownChanged: if (shown) input.forceActiveFocus()

    // ---- App list ----
    readonly property var apps: {
        var out = []
        var all = DesktopEntries.applications ? DesktopEntries.applications.values : []
        for (var i = 0; i < all.length; i++) {
            var a = all[i]
            if (a && !a.noDisplay && ("" + (a.name || "")).length > 0) out.push(a)
        }
        return out
    }

    // Ranked: name prefix beats name substring beats generic name beats keywords.
    readonly property var filtered: {
        var q = ("" + win.query).trim().toLowerCase()
        var src = win.apps
        var i
        if (q.length === 0) {
            var all = src.slice()
            all.sort(function (a, b) {
                return ("" + a.name).toLowerCase().localeCompare(("" + b.name).toLowerCase())
            })
            return all
        }
        var hits = []
        for (i = 0; i < src.length; i++) {
            var e = src[i]
            var n = ("" + (e.name || "")).toLowerCase()
            var g = ("" + (e.genericName || "")).toLowerCase()
            var k = ("" + (e.keywords || "")).toLowerCase()
            var rank = -1
            if (n.indexOf(q) === 0)      rank = 0
            else if (n.indexOf(q) > 0)   rank = 1
            else if (g.indexOf(q) >= 0)  rank = 2
            else if (k.indexOf(q) >= 0)  rank = 3
            if (rank >= 0) hits.push({ e: e, rank: rank, n: n })
        }
        hits.sort(function (a, b) {
            return a.rank !== b.rank ? a.rank - b.rank : a.n.localeCompare(b.n)
        })
        var out = []
        for (i = 0; i < hits.length; i++) out.push(hits[i].e)
        return out
    }

    onQueryChanged: sel = 0

    function move(d) {
        var n = filtered.length
        if (n === 0) return
        sel = (sel + d + n) % n
        list.positionViewAtIndex(sel, ListView.Contain)
    }

    function launch() {
        var e = filtered[sel]
        if (!e) return
        close()
        e.execute()
    }

    // ---- Scrim ----
    Rectangle {
        anchors.fill: parent
        color: win.th.scrim
        opacity: win.shown ? 0.7 : 0
        Behavior on opacity { NumberAnimation { duration: win.th.tPanel; easing.type: Easing.OutQuint } }
        MouseArea { anchors.fill: parent; onClicked: win.close() }
    }

    // ---- Band ----
    Rectangle {
        id: band
        width: parent.width
        height: win.bandHeight
        y: win.shown ? 0 : -(height + 4)
        Behavior on y { NumberAnimation { id: drop; duration: win.th.tPanel; easing.type: Easing.OutQuint } }
        color: win.th.ink

        // Swallow clicks so the scrim's close handler doesn't fire through.
        MouseArea { anchors.fill: parent }

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: win.th.outlineVariant }
        // A red stroke on the lower edge, under the seal.
        Rectangle { anchors.bottom: parent.bottom; x: 28; width: 56; height: 2; color: win.th.primary }

        // ---- Query line ----
        Item {
            id: head
            x: 28
            y: 16
            width: parent.width - 56
            height: 44

            Image {
                id: seal
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30
                source: "file:///home/reouii/.config/quickshell/assets/seal.png"
                sourceSize.width: 120; sourceSize.height: 120
                smooth: true; mipmap: true
            }

            TextInput {
                id: input
                anchors.verticalCenter: parent.verticalCenter
                x: seal.width + 18
                width: parent.width - x - 320
                text: win.query
                onTextChanged: win.query = text
                color: win.th.text
                font.family: win.th.display
                font.pixelSize: win.th.fs(21)
                font.weight: Font.Bold
                selectionColor: win.th.primary
                selectedTextColor: win.th.primaryText
                clip: true
                cursorDelegate: Rectangle {
                    width: 2
                    color: win.th.primary
                    visible: input.activeFocus
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text.length === 0
                    text: "Run…"
                    color: win.th.outlineVariant
                    font: input.font
                }

                Keys.onPressed: function (e) {
                    if (e.key === Qt.Key_Escape) { win.close(); e.accepted = true }
                    else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down || e.key === Qt.Key_Tab) {
                        // Right moves the caret while typing mid-word; only
                        // take it over once the caret is at the end.
                        if (e.key === Qt.Key_Right && input.cursorPosition < input.text.length) return
                        win.move(1); e.accepted = true
                    }
                    else if (e.key === Qt.Key_Left || e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) {
                        if (e.key === Qt.Key_Left && win.sel === 0) return
                        win.move(-1); e.accepted = true
                    }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { win.launch(); e.accepted = true }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                text: win.filtered.length + "   ·   ← → move   ↵ open   esc close"
                color: win.th.outline
                font.family: win.th.body
                font.pixelSize: win.th.fs(10)
            }
        }

        // ---- Results ----
        ListView {
            id: list
            x: 28
            y: 76
            width: parent.width - 56
            height: 118
            orientation: ListView.Horizontal
            spacing: 8
            clip: true
            model: win.filtered
            currentIndex: win.sel
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: tile
                required property var modelData
                required property int index
                readonly property bool on: index === win.sel
                width: win.tileW
                height: ListView.view.height
                radius: win.th.rLarge
                // Reversed selection: pale block, black text.
                color: on ? win.th.text : win.th.surfaceContainer
                Behavior on color { ColorAnimation { duration: win.th.tSnap } }

                IconImage {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 18
                    implicitSize: 40
                    source: Quickshell.iconPath(tile.modelData.icon, "application-x-executable")
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 68
                    width: parent.width - 16
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.modelData.name || ""
                    color: tile.on ? win.th.surface : win.th.text
                    font.family: win.th.body
                    font.pixelSize: win.th.fs(11)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 88
                    width: parent.width - 16
                    horizontalAlignment: Text.AlignHCenter
                    visible: text.length > 0
                    text: tile.modelData.genericName || ""
                    color: tile.on ? win.th.surfaceContainerHighest : win.th.outline
                    font.family: win.th.body
                    font.pixelSize: win.th.fs(9)
                    elide: Text.ElideRight
                }
                // Red mark on the chosen tile.
                Rectangle {
                    visible: tile.on
                    x: 10; y: 10
                    width: 6; height: 6; radius: 1.5
                    color: win.th.primary
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: win.sel = tile.index
                    onClicked: { win.sel = tile.index; win.launch() }
                }
            }
        }

        Text {
            x: 28
            y: 120
            visible: win.filtered.length === 0
            text: "Nothing called “" + win.query + "”"
            color: win.th.outline
            font.family: win.th.body
            font.pixelSize: win.th.fs(13)
        }
    }
}
