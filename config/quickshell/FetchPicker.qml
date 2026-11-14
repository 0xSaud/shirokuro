// Fastfetch picture picker. Opened from the control centre (Appearance ->
// Fastfetch) or with `qs ipc call panels fetch`.
//
// Left: the picture fastfetch shows right now, plus how the next one should be
// cropped and whether to ink it. Right: every picture under ~/Pictures, newest
// first. Clicking one hands it to ~/.local/bin/fetchpic, which crops it square
// and writes ~/.config/fastfetch/logo.png; the preview then reloads.
import QtQuick
import Quickshell
import Quickshell.Io

Overlay {
    id: win

    readonly property string home: "/home/reouii"
    readonly property string dir: home + "/Pictures"
    readonly property string logo: home + "/.config/fastfetch/logo.png"
    readonly property string tool: home + "/.local/bin/fetchpic"

    property var    files: []
    property string focusPart: "center"
    property bool   ink: false
    property string picked: ""
    property string status: ""
    // Bumped after every change so the preview Image reloads the same path.
    property int    rev: 0

    eyebrow: "FASTFETCH"
    title: "Terminal picture"
    hint: "click a picture to use it"
    cardWidth: 940
    cardHeight: 620

    onOpened: { status = ""; rev++; lister.running = true }

    // Every picture under ~/Pictures, three folders deep, newest first.
    Process {
        id: lister
        command: ["bash", "-c",
            "find '" + win.dir + "' -maxdepth 3 -type f " +
            "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' " +
            "-o -iname '*.bmp' -o -iname '*.gif' \\) -printf '%T@\\t%p\\n' 2>/dev/null " +
            "| sort -rn | head -n 300 | cut -f2-"]
        stdout: StdioCollector {
            id: lsOut
            onStreamFinished: {
                var out = [], lines = ("" + lsOut.text).split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var n = lines[i]
                    if (n.trim().length > 0) out.push(n)
                }
                win.files = out
            }
        }
    }

    // Runs fetchpic; the preview reloads when it exits.
    Process {
        id: runner
        onExited: function (code) {
            win.rev++
            win.status = (code === 0) ? "Done" : "That did not work"
        }
    }
    function run(args) {
        if (runner.running) return
        win.status = "Working…"
        runner.command = [win.tool, "--quiet"].concat(args)
        runner.running = true
    }
    function apply(path) {
        win.picked = path
        var a = ["--focus", win.focusPart]
        if (win.ink) a.push("--ink")
        a.push(path)
        win.run(a)
    }
    // Re-crop / re-ink the last picture chosen in this session.
    function reapply() { if (win.picked.length > 0) win.apply(win.picked) }
    function undo() { win.picked = ""; win.run(["--undo"]) }

    function shq(s) { return "'" + ("" + s).replace(/'/g, "'\\''") + "'" }
    function browse() {
        var extra = "--focus " + win.focusPart + (win.ink ? " --ink" : "")
        Quickshell.execDetached(["bash", "-c",
            "src=$(zenity --file-selection --title='Pick a picture for fastfetch' " +
            "--file-filter='Pictures | *.jpg *.jpeg *.png *.webp *.bmp *.gif' 2>/dev/null) || exit 0; " +
            "[ -z \"$src\" ] && exit 0; " + win.shq(win.tool) + " --quiet " + extra + " \"$src\""])
        win.close()
    }

    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool on: false
        property var onPick: null
        height: 30
        radius: win.th.rSmall
        color: on ? win.th.surfaceText
                  : (chipMa.containsMouse ? win.th.surfaceContainerHighest : win.th.surfaceContainerHigh)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text { anchors.centerIn: parent; text: chip.label
               color: chip.on ? win.th.surface : win.th.onSurfaceVariant
               font.family: win.th.body; font.pixelSize: win.th.fs(11); font.weight: Font.DemiBold }
        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (chip.onPick) chip.onPick() }
    }
    component Label: Text {
        color: win.th.outline
        font.family: win.th.body
        font.pixelSize: win.th.fs(11)
        font.weight: Font.DemiBold
    }

    Item {
        anchors.fill: parent

        // ---- Left: current picture and options ----
        Column {
            id: side
            x: win.th.pad
            y: win.th.pad
            width: 236
            spacing: 10

            Label { text: "Showing now" }
            Rectangle {
                width: parent.width
                height: parent.width
                radius: win.th.rLarge
                color: win.th.surfaceContainerHigh
                clip: true
                Image {
                    anchors.fill: parent
                    source: "file://" + win.logo + "?" + win.rev
                    fillMode: Image.PreserveAspectFit
                    cache: false
                    asynchronous: true
                    sourceSize.width: 480
                }
            }
            Text {
                width: parent.width
                text: win.status
                visible: text.length > 0
                color: win.th.primary
                font.family: win.th.body; font.pixelSize: win.th.fs(11)
            }

            Item { width: 1; height: 2 }
            Label { text: "Keep which part" }
            Grid {
                width: parent.width
                columns: 3
                spacing: 6
                Repeater {
                    model: [ { l: "Left", v: "left" }, { l: "Centre", v: "center" }, { l: "Right", v: "right" },
                             { l: "Top", v: "top" }, { l: "Bottom", v: "bottom" } ]
                    Chip {
                        required property var modelData
                        width: (side.width - 12) / 3
                        label: modelData.l
                        on: win.focusPart === modelData.v
                        onPick: function () { win.focusPart = modelData.v; win.reapply() }
                    }
                }
            }

            Item { width: 1; height: 2 }
            Label { text: "Style" }
            Row {
                spacing: 6
                Chip { width: (side.width - 6) / 2; label: "As it is"; on: !win.ink
                       onPick: function () { win.ink = false; win.reapply() } }
                Chip { width: (side.width - 6) / 2; label: "Ink + seal"; on: win.ink
                       onPick: function () { win.ink = true; win.reapply() } }
            }

            Item { width: 1; height: 2 }
            Row {
                spacing: 6
                Chip { width: (side.width - 6) / 2; label: "Undo"
                       onPick: function () { win.undo() } }
                Chip { width: (side.width - 6) / 2; label: "Browse…"
                       onPick: function () { win.browse() } }
            }
        }

        Rectangle {
            x: side.x + side.width + win.th.pad
            y: 0
            width: 1
            height: parent.height
            color: win.th.outlineVariant
        }

        // ---- Right: pictures ----
        GridView {
            id: grid
            x: side.x + side.width + win.th.pad * 2
            y: win.th.pad - 5
            width: parent.width - x - win.th.pad + 5
            height: parent.height - y - 40
            clip: true
            cellWidth: Math.floor(width / 4)
            cellHeight: cellWidth
            model: win.files
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: cell
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight
                readonly property bool isPicked: modelData === win.picked

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 5
                    radius: win.th.r
                    color: win.th.surfaceContainerHigh
                    clip: true
                    border.width: 2
                    border.color: cell.isPicked ? win.th.primary
                                  : (cellMa.containsMouse ? win.th.surfaceText : "transparent")

                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: "file://" + cell.modelData
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 260
                        cache: true
                    }
                    Rectangle {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 2
                        height: 20
                        color: "#B0000000"
                        visible: cellMa.containsMouse || cell.isPicked
                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 6; anchors.rightMargin: 6
                            verticalAlignment: Text.AlignVCenter
                            text: cell.modelData.substring(cell.modelData.lastIndexOf("/") + 1)
                            color: "#ffffff"
                            font.family: win.th.body; font.pixelSize: win.th.fs(9)
                            elide: Text.ElideMiddle
                        }
                    }
                    MouseArea {
                        id: cellMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.apply(cell.modelData)
                    }
                }
            }
        }

        Text {
            x: grid.x + 5
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            text: win.files.length === 0
                  ? "No pictures found in ~/Pictures"
                  : win.files.length + " pictures in ~/Pictures, newest first"
            color: win.th.outline
            font.family: win.th.body; font.pixelSize: win.th.fs(10)
        }
    }
}
