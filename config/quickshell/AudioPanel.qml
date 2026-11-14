// Sound: output devices, microphone, and per-app volume.
//
// Replaces reaching for pavucontrol. Switching the default device is done through
// PipeWire's preferredDefault* properties rather than shelling out to wpctl, so
// the change is immediate and the panel reflects it without polling.
//
// Layout: a mixing desk. Every device and every app playing sound is an
// upright channel strip with a fader; outputs, microphones and apps sit in
// three bays side by side.
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Overlay {
    id: win

    eyebrow: "SOUND"
    title: "Mixer"
    hint: "drag a fader  ·  click a name to make it the default"
    tint: th ? th.tertiary : "#888"
    cardWidth: 900
    cardHeight: 520

    // Real devices, not application streams.
    readonly property var sinks: {
        var out = []
        var all = Pipewire.nodes ? Pipewire.nodes.values : []
        for (var i = 0; i < all.length; i++) {
            var n = all[i]
            if (n && n.isSink && !n.isStream && n.audio) out.push(n)
        }
        return out
    }
    readonly property var sources: {
        var out = []
        var all = Pipewire.nodes ? Pipewire.nodes.values : []
        for (var i = 0; i < all.length; i++) {
            var n = all[i]
            // A source device: not a sink, not an app stream, but has audio.
            if (n && !n.isSink && !n.isStream && n.audio) out.push(n)
        }
        return out
    }
    readonly property var streams: {
        var out = []
        var all = Pipewire.nodes ? Pipewire.nodes.values : []
        for (var i = 0; i < all.length; i++) {
            var n = all[i]
            if (n && n.isStream && n.isSink && n.audio) out.push(n)
        }
        return out
    }

    // Without tracking, volume and muted stay unbound.
    PwObjectTracker { objects: win.sinks }
    PwObjectTracker { objects: win.sources }
    PwObjectTracker { objects: win.streams }

    function label(n) {
        if (!n) return ""
        var s = ("" + (n.description || n.nickname || n.name || "device")).trim()
        return s.length > 0 ? s : "device"
    }
    function pct(n) { return (n && n.audio) ? Math.round(n.audio.volume * 100) : 0 }
    function setPct(n, v) { if (n && n.audio) n.audio.volume = Math.max(0, Math.min(1.5, v / 100)) }

    // ---- one channel strip ----
    component Strip: Item {
        id: st
        property var node: null
        property bool isDefault: false
        property bool isInput: false
        property bool canPick: true
        property var onPick: null
        readonly property bool muted: !!(node && node.audio && node.audio.muted)
        readonly property int level: win.pct(node)
        width: 96

        // Level figure.
        Text {
            id: fig
            anchors.horizontalCenter: parent.horizontalCenter
            text: st.level
            color: st.muted ? win.th.outline : win.th.surfaceText
            font.family: win.th.display; font.pixelSize: win.th.fs(15); font.weight: Font.Bold
        }

        // Fader: a slot with tick marks and a cap that rides it.
        Item {
            id: slot
            anchors.horizontalCenter: parent.horizontalCenter
            y: fig.height + 8
            width: 56
            height: parent.height - y - 86
            readonly property real pos: Math.max(0, Math.min(1, st.level / 100))

            Repeater {
                model: 11
                Rectangle {
                    required property int index
                    x: index % 5 === 0 ? 4 : 9
                    y: Math.round(index * (slot.height - 1) / 10)
                    width: index % 5 === 0 ? 12 : 7
                    height: 1
                    color: win.th.outlineVariant
                }
            }
            Rectangle {
                id: track
                anchors.horizontalCenter: parent.horizontalCenter
                width: 6; height: parent.height
                radius: 3
                color: win.th.surfaceContainerLowest
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: slot.pos * parent.height
                    radius: 3
                    color: st.muted ? win.th.outline : win.th.surfaceText
                }
            }
            Rectangle {
                id: cap
                anchors.horizontalCenter: parent.horizontalCenter
                width: 34; height: 18
                y: (1 - slot.pos) * (slot.height - height)
                radius: win.th.rSmall
                color: capMa.pressed ? win.th.primary : (st.muted ? win.th.outline : win.th.surfaceText)
                Rectangle { anchors.centerIn: parent; width: 18; height: 2; radius: 1; color: win.th.surface }
            }
            MouseArea {
                id: capMa
                anchors.fill: parent
                cursorShape: Qt.SizeVerCursor
                function setFrom(my) {
                    win.setPct(st.node, Math.round((1 - Math.max(0, Math.min(1, my / height))) * 100))
                }
                onPressed: function (m) { setFrom(m.y) }
                onPositionChanged: function (m) { if (pressed) setFrom(m.y) }
                onWheel: function (w) {
                    win.setPct(st.node, Math.max(0, Math.min(100, st.level + (w.angleDelta.y > 0 ? 5 : -5))))
                }
            }
        }

        // Mute.
        Rectangle {
            id: muteBtn
            anchors.horizontalCenter: parent.horizontalCenter
            y: slot.y + slot.height + 10
            width: 34; height: 28
            radius: win.th.r
            color: st.muted ? win.th.primary
                            : (muteMa.containsMouse ? win.th.surfaceContainerHighest : win.th.surfaceContainer)
            Behavior on color { ColorAnimation { duration: 120 } }
            Text {
                anchors.centerIn: parent
                text: st.isInput ? (st.muted ? "\uf131" : "\uf130")
                                 : (st.muted ? "\uf026" : "\uf028")
                color: st.muted ? win.th.primaryText : win.th.onSurfaceVariant
                font.family: win.th.icon; font.pixelSize: win.th.fs(12)
            }
            MouseArea {
                id: muteMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (st.node && st.node.audio) st.node.audio.muted = !st.node.audio.muted
            }
        }

        // Name plate; click to make this the default device.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: parent.width - 8
            height: 38
            radius: win.th.r
            color: st.isDefault ? win.th.surfaceText
                                : (nameMa.containsMouse && st.canPick ? win.th.surfaceContainerHighest : "transparent")
            Behavior on color { ColorAnimation { duration: 120 } }
            Text {
                anchors.centerIn: parent
                width: parent.width - 10
                horizontalAlignment: Text.AlignHCenter
                text: win.label(st.node)
                color: st.isDefault ? win.th.surface : win.th.onSurfaceVariant
                font.family: win.th.body; font.pixelSize: win.th.fs(9); font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 0.95
            }
            MouseArea {
                id: nameMa
                anchors.fill: parent
                hoverEnabled: true
                enabled: st.canPick
                cursorShape: Qt.PointingHandCursor
                onClicked: if (st.onPick) st.onPick()
            }
        }
    }

    // ---- a bay of strips ----
    component Bay: Tile {
        id: bay
        property var nodes: []
        property bool isInput: false
        property bool canPick: true
        property var defaultNode: null
        property var pick: null
        property string emptyText: ""
        th: win.th
        height: parent ? parent.height - 32 : 300

        ListView {
            anchors.fill: parent
            orientation: ListView.Horizontal
            clip: true
            spacing: 2
            model: bay.nodes
            boundsBehavior: Flickable.StopAtBounds
            delegate: Strip {
                required property var modelData
                height: ListView.view.height
                node: modelData
                isInput: bay.isInput
                canPick: bay.canPick
                isDefault: bay.canPick && bay.defaultNode === modelData
                onPick: function () { if (bay.pick) bay.pick(modelData) }
            }
        }
        Text {
            anchors.centerIn: parent
            visible: bay.nodes.length === 0
            text: bay.emptyText
            color: win.th.outline
            font.family: win.th.body; font.pixelSize: win.th.fs(11)
        }
    }

    Item {
        anchors.fill: parent
        // Each bay is as wide as its strips need, within sensible limits; the
        // apps bay takes whatever is left.
        function bayW(n) { return Math.max(128, Math.min(3, Math.max(1, n)) * 98 + 24) }

        Bay {
            id: outBay
            x: 16; y: 16
            width: parent.bayW(win.sinks.length)
            title: "Output"
            nodes: win.sinks
            defaultNode: Pipewire.defaultAudioSink
            pick: function (n) { Pipewire.preferredDefaultAudioSink = n }
            emptyText: "No outputs"
        }
        Bay {
            id: inBay
            x: outBay.x + outBay.width + 10; y: 16
            width: parent.bayW(win.sources.length)
            title: "Microphone"
            isInput: true
            nodes: win.sources
            defaultNode: Pipewire.defaultAudioSource
            pick: function (n) { Pipewire.preferredDefaultAudioSource = n }
            emptyText: "No microphones"
        }
        Bay {
            x: inBay.x + inBay.width + 10; y: 16
            width: parent.width - x - 16
            title: "Apps"
            note: win.streams.length > 0 ? win.streams.length + " playing" : ""
            canPick: false
            nodes: win.streams
            emptyText: "Nothing is playing"
        }
    }
}
