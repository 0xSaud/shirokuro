// Keybind cheatsheet, parsed live out of hyprland.conf.
//
// Layout: the groups are a list down the left; the chosen group's shortcuts are
// on the right, each key drawn as its own keycap.
//
// Reading the config directly means it can never drift out of date the way a
// hand-written list does — rebind something and this reflects it immediately.
import QtQuick
import Quickshell
import Quickshell.Io

Overlay {
    id: win

    property var groups: []      // [{title, binds:[{keys, what}]}]
    property string query: ""

    // Which group is showing; -1 means all of them (and is forced while searching).
    property int section: -1

    eyebrow: "KEYBOARD"
    title: "Shortcuts"
    hint: "type to search"
    tint: th ? th.secondary : "#888"
    cardWidth: 980
    cardHeight: 640

    onOpened: { query = ""; section = -1; conf.reload() }

    FileView {
        id: conf
        path: "/home/reouii/.config/hypr/hyprland.conf"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: win.parseConf(text())
    }

    function cleanTitle(t) {
        return ("" + t).replace(/\(.*?\)/g, "").replace(/-+$/, "").trim()
    }

    function pretty(mods, key) {
        var m = ("" + mods).replace(/\$mainMod/g, "SUPER").trim()
        var parts = []
        if (m.length > 0) {
            var bits = m.split(/\s+/)
            for (var i = 0; i < bits.length; i++)
                if (bits[i].length > 0) parts.push(bits[i].toUpperCase())
        }
        var k = ("" + key).trim()
        var map = {
            "grave": "`", "Escape": "Esc", "Print": "PrtSc", "space": "Space",
            "up": "↑", "down": "↓", "left": "←", "right": "→", "END": "End",
            "mouse:272": "Left-drag", "mouse:273": "Right-drag",
            "XF86MonBrightnessUp": "Brightness +", "XF86MonBrightnessDown": "Brightness −",
            "XF86AudioRaiseVolume": "Volume +", "XF86AudioLowerVolume": "Volume −",
            "XF86AudioMute": "Mute"
        }
        if (map[k]) k = map[k]
        else if (k.length === 1) k = k.toUpperCase()
        parts.push(k)
        return parts.join(" + ")
    }

    readonly property var dispatchers: ({
        "killactive":     "Close the focused window",
        "exit":           "Log out of Hyprland",
        "togglefloating": "Float or tile the window",
        "fullscreen":     "Fullscreen the window",
        "togglesplit":    "Flip the split direction",
        "pseudo":         "Pseudo-tile the window",
        "movewindow":     "Drag the window",
        "resizewindow":   "Drag to resize the window"
    })

    // Prefer a plain description of what the key does. A trailing comment often
    // explains a past rebind ("moved off J") rather than the action itself.
    function describe(action, comment) {
        var a = ("" + action).replace(/,\s*$/, "").trim()
        if (win.dispatchers[a]) return win.dispatchers[a]

        var mf = a.match(/^movefocus,?\s*([lrud])$/)
        if (mf) return "Focus " + ({ l: "left", r: "right", u: "up", d: "down" })[mf[1]]
        var ws = a.match(/^workspace,?\s*(\d+)$/)
        if (ws) return "Go to workspace " + ws[1]
        var mw = a.match(/^movetoworkspace,?\s*(\d+)$/)
        if (mw) return "Move window to workspace " + mw[1]

        var c = ("" + comment).trim()
        var aboutRebind = /^(was |moved off|kept |now |dwindle )/i.test(c)
        if (c.length > 0 && !aboutRebind) return c
        if (a.indexOf("Open ") === 0 || a.indexOf("Lock ") === 0) return a
        // A bare command: show it as a capitalised app name.
        var word = a.split(/\s+/)[0].replace(/[,;]$/, "")
        if (word.length > 0 && /^[a-z][a-z0-9._-]*$/.test(word))
            return word.charAt(0).toUpperCase() + word.slice(1)
        return a
    }

    function parseConf(txt) {
        var lines = ("" + txt).split("\n")
        var out = [], cur = null
        for (var i = 0; i < lines.length; i++) {
            var raw = lines[i]
            var line = raw.trim()

            // "# ---- Section name" style headers become groups.
            var head = line.match(/^#\s*-{4,}\s*(.+?)\s*$/)
            if (head) { cur = { title: win.cleanTitle(head[1]), binds: [] }; out.push(cur); continue }
            var head2 = line.match(/^#\s*---\s*(.+?)\s*---\s*$/)
            if (head2) { cur = { title: win.cleanTitle(head2[1]), binds: [] }; out.push(cur); continue }

            if (!/^bind[emrltn]*\s*=/.test(line)) continue
            if (line.charAt(0) === "#") continue

            // Trailing comment is a better description than the raw dispatcher.
            var comment = ""
            var hash = line.indexOf("#")
            if (hash > 0) { comment = line.substring(hash + 1).trim(); line = line.substring(0, hash) }

            var eq = line.indexOf("=")
            if (eq < 0) continue
            var body = line.substring(eq + 1)
            var f = body.split(",")
            if (f.length < 3) continue

            var keys = pretty(f[0], f[1])
            var action = f.slice(2).join(",").trim()
            // Strip our own plumbing so the sheet reads in plain language.
            action = action.replace(/^exec,\s*/, "")
                           .replace(/qs ipc call panels\s+/, "Open ")
                           .replace(/qs ipc call lock\s+/, "Lock ")
                           .replace(/~\/\.config\/[^\s]*\/([a-z-]+)\.sh/, "$1")
            var what = win.describe(action, comment)
            if (what.length > 90) what = what.substring(0, 88) + "…"

            if (!cur) { cur = { title: "General", binds: [] }; out.push(cur) }
            cur.binds.push({ keys: keys, what: what })
        }
        // Drop groups that ended up with no binds in them.
        var keep = []
        for (var g = 0; g < out.length; g++) if (out[g].binds.length > 0) keep.push(out[g])
        win.groups = keep
    }

    readonly property var filtered: {
        var q = ("" + win.query).trim().toLowerCase()
        if (q.length === 0) return win.groups
        var out = []
        for (var i = 0; i < win.groups.length; i++) {
            var g = win.groups[i], hits = []
            for (var j = 0; j < g.binds.length; j++) {
                var b = g.binds[j]
                if (b.keys.toLowerCase().indexOf(q) >= 0 || b.what.toLowerCase().indexOf(q) >= 0)
                    hits.push(b)
            }
            if (hits.length > 0) out.push({ title: g.title, binds: hits })
        }
        return out
    }

    component NavRow: Rectangle {
        id: nr
        property string label: ""
        property int count: 0
        property bool on: false
        property var onPick: null
        width: parent ? parent.width : 240
        height: 34
        radius: win.th.r
        color: on ? win.th.surfaceText
                  : (nrMa.containsMouse ? win.th.surfaceContainerHigh : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 52
            text: nr.label
            color: nr.on ? win.th.surface : win.th.onSurfaceVariant
            font.family: win.th.body; font.pixelSize: win.th.fs(11); font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: nr.count
            color: nr.on ? win.th.surface : win.th.outline
            font.family: win.th.mono; font.pixelSize: win.th.fs(9)
        }
        MouseArea { id: nrMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (nr.onPick) nr.onPick() }
    }

    readonly property int total: {
        var n = 0
        for (var i = 0; i < win.groups.length; i++) n += win.groups[i].binds.length
        return n
    }
    // What the right-hand side lists: every match while searching, otherwise
    // the chosen group (or everything).
    readonly property var showing: {
        var src = win.filtered
        if (("" + win.query).trim().length > 0 || win.section < 0) return src
        return (win.section < win.groups.length) ? [win.groups[win.section]] : src
    }

    Item {
        anchors.fill: parent

        // ================= left: search and groups =================
        Rectangle {
            id: searchBox
            x: 16; y: 16
            width: 240; height: 40
            radius: win.th.rLarge
            color: win.th.surfaceContainerHigh
            Text {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf002"
                color: win.th.outline
                font.family: win.th.icon; font.pixelSize: win.th.fs(11)
            }
            TextInput {
                id: input
                x: 38
                width: parent.width - x - 12
                anchors.verticalCenter: parent.verticalCenter
                text: win.query
                onTextChanged: win.query = text
                color: win.th.surfaceText
                font.family: win.th.body; font.pixelSize: win.th.fs(12)
                clip: true
                focus: win.shown
                Component.onCompleted: forceActiveFocus()
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text.length === 0
                    text: "Search"
                    color: win.th.outline
                    font: input.font
                }
                Keys.onPressed: function (e) {
                    if (e.key === Qt.Key_Escape) { win.close(); e.accepted = true }
                }
            }
        }

        Flickable {
            x: 16
            y: searchBox.y + searchBox.height + 10
            width: 240
            height: parent.height - y - 16
            clip: true
            contentHeight: navCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: navCol
                width: parent.width
                spacing: 4

                NavRow {
                    label: "Everything"; count: win.total
                    on: win.section < 0
                    onPick: function () { win.section = -1; input.text = "" }
                }
                Repeater {
                    model: win.groups
                    NavRow {
                        required property var modelData
                        required property int index
                        label: modelData.title
                        count: modelData.binds.length
                        on: win.section === index && ("" + win.query).trim().length === 0
                        onPick: function () { win.section = index; input.text = "" }
                    }
                }
            }
        }

        // ================= right: the shortcuts =================
        Tile {
            id: pane
            th: win.th
            x: 266; y: 16
            width: parent.width - x - 16
            height: parent.height - 32

            Flickable {
                id: flick
                anchors.fill: parent
                clip: true
                contentHeight: list.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                // Back to the top whenever the listing changes.
                Connections {
                    target: win
                    function onShowingChanged() { flick.contentY = 0 }
                }

                Column {
                    id: list
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: win.showing
                        Column {
                            id: grp
                            required property var modelData
                            width: list.width
                            spacing: 2

                            Item {
                                width: parent.width
                                height: 30
                                Rectangle { anchors.verticalCenter: parent.verticalCenter
                                            width: 10; height: 2; color: win.th.primary }
                                Text {
                                    x: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: grp.modelData.title
                                    color: win.th.surfaceText
                                    font.family: win.th.display; font.pixelSize: win.th.fs(12); font.weight: Font.Bold
                                }
                            }
                            Repeater {
                                model: grp.modelData.binds
                                Rectangle {
                                    id: line
                                    required property var modelData
                                    width: grp.width
                                    height: 34
                                    radius: win.th.r
                                    color: lineMa.containsMouse ? win.th.surfaceContainerHighest : "transparent"

                                    Text {
                                        x: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - caps.width - 30
                                        text: line.modelData.what
                                        color: win.th.onSurfaceVariant
                                        font.family: win.th.body; font.pixelSize: win.th.fs(11)
                                        elide: Text.ElideRight
                                    }
                                    // One keycap per key, right-aligned.
                                    Row {
                                        id: caps
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        Repeater {
                                            model: ("" + line.modelData.keys).split(" + ")
                                            Rectangle {
                                                required property var modelData
                                                width: Math.max(24, capText.implicitWidth + 14)
                                                height: 22
                                                radius: win.th.rSmall
                                                color: win.th.surfaceContainer
                                                border.width: 1
                                                border.color: win.th.outlineVariant
                                                // The lip under a keycap.
                                                Rectangle { anchors.bottom: parent.bottom; x: 1
                                                            width: parent.width - 2; height: 2
                                                            radius: 1; color: win.th.outlineVariant }
                                                Text {
                                                    id: capText
                                                    anchors.centerIn: parent
                                                    anchors.verticalCenterOffset: -1
                                                    text: modelData
                                                    color: win.th.surfaceText
                                                    font.family: win.th.mono; font.pixelSize: win.th.fs(9)
                                                    font.weight: Font.Medium
                                                }
                                            }
                                        }
                                    }
                                    MouseArea { id: lineMa; anchors.fill: parent; hoverEnabled: true }
                                }
                            }
                            Item { width: 1; height: 8 }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: win.showing.length === 0
                text: "Nothing matches"
                color: win.th.outline
                font.family: win.th.body; font.pixelSize: win.th.fs(13)
            }
        }
    }
}
