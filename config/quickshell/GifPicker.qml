// GIF picker with a framing editor.
//
// Picking is only half of it: a wide or tall GIF centre-cropped into a panel
// usually cuts the subject out, so each GIF gets its own zoom and pan saved
// alongside the path.
//
// Layout: the framing stage takes the top, at the exact proportions of the
// Control Center tile it will fill; a film strip of pictures runs along the
// bottom; the controls sit beside the stage.
import QtQuick
import Quickshell
import Quickshell.Io

Overlay {
    id: win

    property string dir: "/home/reouii/Pictures/gifs"
    property string currentPath: ""
    property real   curZoom: 1.0
    property real   curOffX: 0.5
    property real   curOffY: 0.5

    // Live edits, applied to the preview before they are saved.
    property string pick: ""
    property real   zoom: 1.0
    property real   offX: 0.5
    property real   offY: 0.5

    property var files: []

    eyebrow: "GIF"
    title: "Panel picture"
    hint: "drag to move  ·  scroll to zoom"
    tint: th ? th.tertiary : "#888"
    cardWidth: 880
    cardHeight: 600

    onOpened: {
        pick = currentPath; zoom = curZoom; offX = curOffX; offY = curOffY
        lister.running = true
    }

    Process {
        id: lister
        command: ["bash", "-c",
            "ls -1 " + "'" + win.dir + "'" +
            " 2>/dev/null | grep -iE " +
            "'\\.(gif|webp|png|jpg|jpeg|bmp|avif|heic|heif|jxl|tif|tiff|svg|ico|tga)$'" +
            " || true"]
        stdout: StdioCollector {
            id: lsOut
            onStreamFinished: {
                var out = []
                var lines = ("" + lsOut.text).split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var n = lines[i].trim()
                    if (n.length > 0) out.push(n)
                }
                win.files = out
            }
        }
    }

    function shq(s) { return "'" + ("" + s).replace(/'/g, "'\\''") + "'" }

    function save() {
        var f = "/home/reouii/.config/quickshell/gif.json"
        var cmd =
            "f=" + shq(f) + "; [ -s \"$f\" ] || echo '{}' > \"$f\"; " +
            "tmp=$(mktemp) && jq --arg p " + shq(win.pick) +
            " --argjson z " + Number(win.zoom).toFixed(4) +
            " --argjson x " + Number(win.offX).toFixed(4) +
            " --argjson y " + Number(win.offY).toFixed(4) +
            " '.path=$p | .zoom=$z | .offsetX=$x | .offsetY=$y' \"$f\" > \"$tmp\" && mv \"$tmp\" \"$f\""
        Quickshell.execDetached(["bash", "-c", cmd])
        win.close()
    }

    function clearGif() {
        var f = "/home/reouii/.config/quickshell/gif.json"
        Quickshell.execDetached(["bash", "-c",
            "f=" + shq(f) + "; tmp=$(mktemp) && jq '.path=\"\"' \"$f\" > \"$tmp\" && mv \"$tmp\" \"$f\""])
        win.close()
    }

    function addNew() {
        Quickshell.execDetached(["bash", "-c",
            "src=$(zenity --file-selection --title='Pick an image or GIF' " +
            "--file-filter='Images | *.gif *.webp *.png *.jpg *.jpeg *.bmp *.avif " +
            "*.heic *.heif *.jxl *.tif *.tiff *.svg *.ico *.tga' 2>/dev/null) || exit 0; " +
            "[ -n \"$src\" ] && cp -f \"$src\" " + shq(win.dir) + "/"])
    }

    Item {
        anchors.fill: parent

        // ---- Stage: same proportions as the Control Center tile (270 x 148) ----
        Rectangle {
            id: stage
            x: 16; y: 16
            width: 584
            height: Math.round(width * 148 / 270)
            radius: win.th.rLarge
            color: win.th.surfaceContainerHigh
            clip: true

            GifView {
                id: prev
                anchors.fill: parent
                th: win.th
                source: win.pick.length > 0 ? ("file://" + win.pick) : ""
                zoom: win.zoom
                offsetX: win.offX
                offsetY: win.offY
                playing: win.shown
            }
            Text {
                anchors.centerIn: parent
                visible: win.pick.length === 0
                text: "Pick a picture below"
                color: win.th.outline
                font.family: win.th.body; font.pixelSize: win.th.fs(13)
            }
            MouseArea {
                anchors.fill: parent
                enabled: win.pick.length > 0
                cursorShape: Qt.SizeAllCursor
                property real lastX: 0
                property real lastY: 0
                onPressed: function (m) { lastX = m.x; lastY = m.y }
                onPositionChanged: function (m) {
                    if (!pressed) return
                    // Drag moves the image, so the offset moves the other way.
                    win.offX = Math.max(0, Math.min(1, win.offX - (m.x - lastX) / prev.overflowX))
                    win.offY = Math.max(0, Math.min(1, win.offY - (m.y - lastY) / prev.overflowY))
                    lastX = m.x; lastY = m.y
                }
                onWheel: function (w) {
                    var step = w.angleDelta.y > 0 ? 1.08 : 1 / 1.08
                    // Goes below 1.0 so a tall or wide GIF can be pulled
                    // right back until the whole thing is in frame.
                    win.zoom = Math.max(0.25, Math.min(4.0, win.zoom * step))
                }
            }
        }

        // ---- Controls beside the stage ----
        Tile {
            id: ctl
            th: win.th
            x: stage.x + stage.width + 10
            y: 16
            width: parent.width - x - 16
            height: stage.height
            title: "Framing"

            Text {
                id: zoomFig
                text: Number(win.zoom).toFixed(2) + "×"
                color: win.th.surfaceText
                font.family: win.th.display; font.pixelSize: win.th.fs(30); font.weight: Font.Bold
            }
            Text {
                y: zoomFig.height
                text: "zoom"
                color: win.th.outline
                font.family: win.th.body; font.pixelSize: win.th.fs(10)
            }
            Row {
                y: 76
                spacing: 6
                // Pulls back until nothing is cropped off.
                Chip { th: win.th; width: (ctl.bodyWidth - 6) / 2; label: "Fit all"
                       onPick: function () { win.zoom = prev.fitZoom; win.offX = 0.5; win.offY = 0.5 } }
                Chip { th: win.th; width: (ctl.bodyWidth - 6) / 2; label: "Fill"
                       onPick: function () { win.zoom = 1.0; win.offX = 0.5; win.offY = 0.5 } }
            }
            Text {
                y: 122
                width: parent.width
                wrapMode: Text.WordWrap
                text: "This is the picture on the Control Center and the music deck. Framing is saved per picture."
                color: win.th.outline
                font.family: win.th.body; font.pixelSize: win.th.fs(10)
                lineHeight: 1.2
            }
            Column {
                anchors.bottom: parent.bottom
                width: parent.width
                spacing: 6
                Chip { th: win.th; width: parent.width; label: "Use this picture"
                       on: win.pick.length > 0
                       onPick: function () { if (win.pick.length > 0) win.save() } }
                Chip { th: win.th; width: parent.width; label: "No picture"
                       onPick: function () { win.clearGif() } }
            }
        }

        // ---- Film strip ----
        Tile {
            id: strip
            th: win.th
            x: 16
            y: stage.y + stage.height + 10
            width: parent.width - 32
            height: parent.height - y - 16
            title: "Pictures"
            note: win.files.length + " in " + win.dir.replace("/home/reouii", "~")

            ListView {
                anchors.fill: parent
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                model: win.files
                boundsBehavior: Flickable.StopAtBounds

                // "Add" is the first frame of the strip.
                header: Item {
                    width: 92
                    height: ListView.view ? ListView.view.height : 0
                    Rectangle {
                        width: 84; height: parent.height
                        radius: win.th.r
                        color: addMa.containsMouse ? win.th.surfaceText : win.th.surfaceContainer
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "+"
                                   color: addMa.containsMouse ? win.th.surface : win.th.onSurfaceVariant
                                   font.family: win.th.display; font.pixelSize: win.th.fs(22) }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Add"
                                   color: addMa.containsMouse ? win.th.surface : win.th.outline
                                   font.family: win.th.body; font.pixelSize: win.th.fs(10) }
                        }
                        MouseArea { id: addMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor; onClicked: win.addNew() }
                    }
                }

                delegate: Rectangle {
                    id: frame
                    required property var modelData
                    readonly property string full: win.dir + "/" + modelData
                    readonly property bool on: full === win.pick
                    width: Math.round(height * 1.5)
                    height: ListView.view.height
                    radius: win.th.r
                    color: win.th.surfaceContainer
                    clip: true

                    // First frame only: a strip of animating GIFs would burn
                    // CPU for no benefit.
                    Image {
                        anchors.fill: parent
                        source: "file://" + frame.full
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 300
                        cache: true
                        opacity: (frame.on || frameMa.containsMouse) ? 1.0 : 0.7
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: win.th.r
                        color: "transparent"
                        border.width: 2
                        border.color: frame.on ? win.th.primary
                                      : (frameMa.containsMouse ? win.th.surfaceText : "transparent")
                    }
                    MouseArea {
                        id: frameMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            win.pick = frame.full
                            // A newly chosen picture starts from a neutral frame.
                            win.zoom = 1.0; win.offX = 0.5; win.offY = 0.5
                        }
                    }
                }
            }
        }
    }
}
