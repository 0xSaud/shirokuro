// Colour control.
//
// Default is "from wallpaper": the scheme is regenerated from whatever image is
// on the desktop. Manual mode pins a source colour instead, and survives
// wallpaper changes. The named themes are kept, but as source colours feeding
// the same generator rather than as fixed palettes.
//
// Layout: a colour wheel instead of a swatch grid. Three rings (vivid outside,
// soft inside), click anywhere on them to build the whole palette around that
// colour. Everything else sits in tiles around the wheel; nothing scrolls.
import QtQuick
import Quickshell
import Quickshell.Io

Overlay {
    id: win

    property var cfg
    property var swatches: []

    eyebrow: "COLOUR"
    title: "Palette"
    hint: "applies immediately"
    cardWidth: 900
    cardHeight: 560

    onOpened: lister.running = true

    Process {
        id: lister
        command: ["bash", "-c",
            "for f in $HOME/.config/themes/themes/*.json; do " +
            "jq -r '(.label // .name) + \"|\" + .accent' \"$f\" 2>/dev/null; done"]
        stdout: StdioCollector {
            id: lsOut
            onStreamFinished: {
                var out = [], lines = ("" + lsOut.text).split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var p = lines[i].trim().split("|")
                    if (p.length === 2 && p[1].length > 0) out.push({ label: p[0], hex: p[1] })
                }
                win.swatches = out
            }
        }
    }

    function shq(s) { return "'" + ("" + s).replace(/'/g, "'\\''") + "'" }
    function hexOf(c) {
        function h(x) { var s = Math.round(x * 255).toString(16); return s.length < 2 ? "0" + s : s }
        return "#" + h(c.r) + h(c.g) + h(c.b)
    }
    function regen(args) {
        Quickshell.execDetached(["bash", "-c",
            "$HOME/.config/themes/bin/apply-colors.sh " + args])
    }
    // Every regeneration carries the full current settings, so changing one
    // control never silently resets another.
    function src() {
        return win.cfg.colorMode === "manual" ? "--source " + shq(win.cfg.sourceColor) : "--wallpaper"
    }
    function opts() {
        return " --vivid " + Number(win.cfg.vivid).toFixed(2) +
               " --harmony " + Number(win.cfg.harmony).toFixed(0)
    }
    function useWallpaper() { regen("--wallpaper" + opts()) }
    function useSource(hex) { regen("--source " + shq(hex) + opts()) }
    function isSource(hex) {
        return win.cfg.colorMode === "manual"
            && ("" + hex).toLowerCase() === ("" + win.cfg.sourceColor).toLowerCase()
    }

    // The wheel: 24 hues in three saturation rings.
    readonly property int  segs: 24
    readonly property var  sats: [0.72, 0.45, 0.24]
    function wheelColor(seg, band) { return Qt.hsla(seg / win.segs, win.sats[band], 0.55, 1.0) }

    Item {
        anchors.fill: parent
        readonly property int pad: 16
        readonly property int gap: 10

        // ================= left column =================
        Tile {
            id: tSource
            th: win.th
            x: 16; y: 16; width: 300; height: 100
            title: "Colours come from"
            Row {
                spacing: 8
                Chip { th: win.th; width: (tSource.bodyWidth - 8) / 2; label: "The wallpaper"
                       on: win.cfg.colorMode === "wallpaper"
                       onPick: function () { win.useWallpaper() } }
                Chip { th: win.th; width: (tSource.bodyWidth - 8) / 2; label: "My colour"
                       on: win.cfg.colorMode === "manual"
                       onPick: function () { win.useSource(win.cfg.sourceColor) } }
            }
            Text {
                y: 38
                width: parent.width
                text: (win.cfg.colorMode === "wallpaper" && win.th.raw && win.th.raw.achromatic)
                      ? "Wallpaper is black and white: scheme stays grey"
                      : "Source " + win.th.sourceColor
                color: win.th.outline
                font.family: win.th.body; font.pixelSize: win.th.fs(10)
                elide: Text.ElideRight
            }
        }

        Tile {
            id: tVivid
            th: win.th
            x: 16; y: tSource.y + tSource.height + 10; width: 300; height: 78
            title: "Intensity"
            Row {
                spacing: 6
                Repeater {
                    model: [ { label: "Muted", v: 0.7 }, { label: "Natural", v: 1.0 },
                             { label: "Vivid", v: 1.3 }, { label: "Intense", v: 1.6 } ]
                    Chip {
                        required property var modelData
                        th: win.th
                        width: (tVivid.bodyWidth - 18) / 4
                        label: modelData.label
                        // Nearest preset counts as chosen, so in-between values still show one.
                        on: Math.abs(win.cfg.vivid - modelData.v) < 0.16
                        // Passed explicitly rather than written first and read
                        // back: the settings write is async, so reading it here
                        // would regenerate with the previous value.
                        onPick: function () { win.regen(win.src() + " --vivid " + modelData.v
                                                        + " --harmony " + Number(win.cfg.harmony).toFixed(0)) }
                    }
                }
            }
        }

        Tile {
            id: tHarm
            th: win.th
            x: 16; y: tVivid.y + tVivid.height + 10; width: 300; height: 114
            title: "Second accent"
            note: "how far it drifts"
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: [ { label: "Same", v: 0 }, { label: "Close", v: 20 }, { label: "Near", v: 30 },
                             { label: "Wide", v: 60 }, { label: "Opposite", v: 180 } ]
                    Chip {
                        required property var modelData
                        th: win.th
                        label: modelData.label
                        hasDot: true
                        // Shows the accent this setting would produce.
                        dot: Qt.hsla(((win.th.raw && win.th.raw.hue ? win.th.raw.hue : 30)
                                      + modelData.v) % 360 / 360.0, 0.55, 0.62, 1.0)
                        on: Math.abs(win.cfg.harmony - modelData.v) < 0.5
                        onPick: function () { win.regen(win.src() + " --vivid " + Number(win.cfg.vivid).toFixed(2)
                                                        + " --harmony " + modelData.v) }
                    }
                }
            }
        }

        Tile {
            id: tUse
            th: win.th
            x: 16; y: tHarm.y + tHarm.height + 10; width: 300
            height: parent.height - y - 16
            title: "In use"
            // The live scheme as a strip of upright bars.
            Row {
                id: bars
                width: parent.width
                height: parent.height - 16
                spacing: 4
                Repeater {
                    model: [ { n: "bg",     c: win.th.surface },
                             { n: "tile",   c: win.th.surfaceContainerHigh },
                             { n: "accent", c: win.th.primary },
                             { n: "soft",   c: win.th.secondary },
                             { n: "2nd",    c: win.th.tertiary },
                             { n: "alert",  c: win.th.error },
                             { n: "line",   c: win.th.outline },
                             { n: "text",   c: win.th.surfaceText } ]
                    Rectangle {
                        required property var modelData
                        width: (bars.width - 7 * 4) / 8
                        height: bars.height
                        radius: win.th.rSmall
                        color: modelData.c
                        border.width: 1
                        border.color: win.th.outlineVariant
                    }
                }
            }
            Row {
                y: bars.height + 3
                width: parent.width
                spacing: 4
                Repeater {
                    model: ["bg", "tile", "accent", "soft", "2nd", "alert", "line", "text"]
                    Text {
                        required property var modelData
                        width: (bars.width - 7 * 4) / 8
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: win.th.outline
                        font.family: win.th.body; font.pixelSize: win.th.fs(8)
                    }
                }
            }
        }

        // ================= right column =================
        Tile {
            id: tWheel
            th: win.th
            x: 326; y: 16
            width: parent.width - x - 16
            height: 286
            title: "Pick a colour"
            note: "outside vivid  ·  inside soft"

            Canvas {
                id: wheel
                width: 236; height: 236
                y: (parent.height - height) / 2
                x: 6
                readonly property real cx: width / 2
                readonly property real cy: height / 2
                // Outer and inner radius of each ring.
                readonly property var rings: [[118, 91], [89, 65], [63, 41]]
                readonly property string picked: ("" + win.cfg.sourceColor).toLowerCase()
                readonly property bool manual: win.cfg.colorMode === "manual"
                onPickedChanged: requestPaint()
                onManualChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var step = 2 * Math.PI / win.segs
                    var hit = null
                    for (var b = 0; b < 3; b++) {
                        for (var i = 0; i < win.segs; i++) {
                            var a0 = i * step - Math.PI / 2 - step / 2 + 0.012
                            var a1 = a0 + step - 0.024
                            var c = win.wheelColor(i, b)
                            ctx.beginPath()
                            ctx.arc(cx, cy, rings[b][0], a0, a1, false)
                            ctx.arc(cx, cy, rings[b][1], a1, a0, true)
                            ctx.closePath()
                            ctx.fillStyle = c
                            ctx.fill()
                            if (manual && win.hexOf(c).toLowerCase() === picked) hit = [b, a0, a1]
                        }
                    }
                    // Outline the segment in use.
                    if (hit) {
                        ctx.beginPath()
                        ctx.arc(cx, cy, rings[hit[0]][0] + 1, hit[1], hit[2], false)
                        ctx.arc(cx, cy, rings[hit[0]][1] - 1, hit[2], hit[1], true)
                        ctx.closePath()
                        ctx.lineWidth = 3
                        ctx.strokeStyle = "#ffffff"
                        ctx.stroke()
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    onClicked: function (m) {
                        var dx = m.x - wheel.cx, dy = m.y - wheel.cy
                        var r = Math.sqrt(dx * dx + dy * dy)
                        var band = -1
                        for (var b = 0; b < 3; b++)
                            if (r <= wheel.rings[b][0] && r >= wheel.rings[b][1]) band = b
                        if (band < 0) return
                        var step = 2 * Math.PI / win.segs
                        var a = Math.atan2(dy, dx) + Math.PI / 2 + step / 2
                        while (a < 0) a += 2 * Math.PI
                        var seg = Math.floor(a / step) % win.segs
                        win.useSource(win.hexOf(win.wheelColor(seg, band)))
                    }
                }
                // Hub: the colour everything is currently built from.
                Rectangle {
                    anchors.centerIn: parent
                    width: 66; height: 66; radius: 33
                    color: win.th.sourceColor
                    border.width: 2
                    border.color: win.th.surfaceContainerHigh
                }
            }

            // Ready-made starting points beside the wheel.
            Column {
                x: wheel.x + wheel.width + 26
                y: 6
                width: parent.width - x
                spacing: 6
                Text { text: "Or start from"
                       color: win.th.outline
                       font.family: win.th.body; font.pixelSize: win.th.fs(10) }
                Grid {
                    columns: 2
                    spacing: 6
                    Repeater {
                        model: [
                            // #808080 has no chroma at all, so the generator drops to
                            // its monochrome path: greys, no invented hue.
                            { label: "Mono", hex: "#808080" }, { label: "Warm", hex: "#b08050" },
                            { label: "Cool", hex: "#5a80b0" }, { label: "Ink",  hex: "#5a5f78" },
                            { label: "Rose", hex: "#b06a80" }, { label: "Moss", hex: "#6f9060" },
                            { label: "Seal red", hex: "#cf2a27" }, { label: "Violet", hex: "#7a5fd0" }
                        ]
                        Chip {
                            required property var modelData
                            th: win.th
                            width: 122
                            label: modelData.label
                            hasDot: true
                            dot: modelData.hex
                            on: win.isSource(modelData.hex)
                            onPick: function () { win.useSource(modelData.hex) }
                        }
                    }
                }
                Item { width: 1; height: 6 }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Click any segment of the wheel. The bar, panels, window borders, terminal and prompt are all rebuilt around it."
                    color: win.th.outline
                    font.family: win.th.body; font.pixelSize: win.th.fs(10)
                    lineHeight: 1.2
                }
            }
        }

        Tile {
            id: tThemes
            th: win.th
            x: 326; y: tWheel.y + tWheel.height + 10
            width: parent.width - x - 16
            height: parent.height - y - 16
            title: "Saved themes"
            note: "used as a starting colour"
            Flickable {
                anchors.fill: parent
                clip: true
                contentHeight: themeFlow.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                Flow {
                    id: themeFlow
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: win.swatches
                        Chip {
                            required property var modelData
                            th: win.th
                            label: modelData.label
                            hasDot: true
                            dot: modelData.hex
                            on: win.isSource(modelData.hex)
                            onPick: function () { win.useSource(modelData.hex) }
                        }
                    }
                }
            }
        }
    }
}
