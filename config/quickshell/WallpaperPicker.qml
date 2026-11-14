// Wallpaper picker. Choosing one also regenerates the whole colour scheme when
// colours follow the wallpaper, because apply-wallpaper.sh calls
// apply-colors.sh on the way out.
//
// Layout: one large preview on the left that follows the pointer, and a single
// column of thumbnails on the right. Hover to look, click to set.
import QtQuick
import Quickshell
import Quickshell.Io

Overlay {
    id: win

    property string dir: "/home/reouii/Pictures/Wallpapers"
    property string currentPath: ""
    property var files: []
    // The thumbnail under the pointer; empty means "show the current one".
    property string peek: ""

    readonly property string shownPath: peek.length > 0 ? peek : currentPath
    readonly property string shownName: shownPath.substring(shownPath.lastIndexOf("/") + 1)

    eyebrow: "WALLPAPER"
    title: "Background"
    hint: "hover to preview  ·  click to set"
    cardWidth: 960
    cardHeight: 600

    onOpened: { peek = ""; lister.running = true }

    Process {
        id: lister
        command: ["bash", "-c",
            "ls -1 '" + "/home/reouii/Pictures/Wallpapers" + "' 2>/dev/null" +
            " | grep -iE '\\.(jpg|jpeg|png|webp|bmp|mp4|mkv|webm|mov|avi|m4v)$' || true"]
        stdout: StdioCollector {
            id: lsOut
            onStreamFinished: {
                var out = [], lines = ("" + lsOut.text).split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var n = lines[i].trim()
                    if (n.length > 0) out.push(n)
                }
                win.files = out
            }
        }
    }

    function shq(s) { return "'" + ("" + s).replace(/'/g, "'\\''") + "'" }
    function isVideo(p) { return /\.(mp4|mkv|webm|mov|avi|m4v)$/i.test("" + p) }

    function apply(name) {
        Quickshell.execDetached(["bash", "-c",
            "$HOME/.config/themes/bin/apply-wallpaper.sh " + shq(win.dir + "/" + name)])
        win.close()
    }

    function addNew() {
        Quickshell.execDetached(["bash", "-c",
            "src=$(zenity --file-selection --title='Pick a wallpaper' " +
            "--file-filter='Wallpapers | *.jpg *.jpeg *.png *.webp *.bmp *.mp4 *.mkv *.webm *.mov *.avi *.m4v' " +
            "2>/dev/null) || exit 0; [ -z \"$src\" ] && exit 0; " +
            "cp -f \"$src\" " + shq(win.dir) + "/ && " +
            "$HOME/.config/themes/bin/apply-wallpaper.sh " + shq(win.dir) + "/\"$(basename \"$src\")\""])
        win.close()
    }

    Item {
        anchors.fill: parent

        // ---- Large preview ----
        Rectangle {
            id: stage
            x: 16; y: 16
            width: 640
            height: 360
            radius: win.th.rLarge
            color: win.th.surfaceContainerHigh
            clip: true

            Image {
                anchors.fill: parent
                // Videos have no decodable first frame here.
                source: (win.shownPath.length > 0 && !win.isVideo(win.shownPath)) ? ("file://" + win.shownPath) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 1280
                cache: true
            }
            Text {
                anchors.centerIn: parent
                visible: win.isVideo(win.shownPath) || win.shownPath.length === 0
                text: win.shownPath.length === 0 ? "No wallpaper set" : "Video wallpaper"
                color: win.th.outline
                font.family: win.th.body; font.pixelSize: win.th.fs(13)
            }
        }

        // ---- Caption under the preview ----
        Row {
            x: 16
            y: stage.y + stage.height + 14
            spacing: 10
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 3; height: 30; radius: 1.5
                color: win.th.primary
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: 520
                    text: win.shownName.length > 0 ? win.shownName : "—"
                    color: win.th.surfaceText
                    font.family: win.th.display; font.pixelSize: win.th.fs(14); font.weight: Font.Bold
                    elide: Text.ElideMiddle
                }
                Text {
                    text: (win.peek.length > 0 && win.peek !== win.currentPath) ? "Click to set as wallpaper" : "On the desktop now"
                    color: win.th.outline
                    font.family: win.th.body; font.pixelSize: win.th.fs(10)
                }
            }
        }

        Row {
            x: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            spacing: 10
            Chip { th: win.th; strong: true; glyph: "+"; label: "Add a picture"
                   onPick: function () { win.addNew() } }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: win.files.length + " in " + win.dir.replace("/home/reouii", "~")
                color: win.th.outline
                font.family: win.th.body; font.pixelSize: win.th.fs(10)
            }
        }

        // ---- Thumbnails ----
        ListView {
            id: list
            x: stage.x + stage.width + 14
            y: 16
            width: parent.width - x - 16
            height: parent.height - 32
            clip: true
            spacing: 8
            model: win.files
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: cell
                required property var modelData
                readonly property string full: win.dir + "/" + modelData
                readonly property bool isCurrent: full === win.currentPath
                width: ListView.view.width
                height: Math.round(width * 9 / 16)
                radius: win.th.r
                color: win.th.surfaceContainerHigh
                clip: true

                Image {
                    anchors.fill: parent
                    source: win.isVideo(cell.modelData) ? "" : ("file://" + cell.full)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 420
                    cache: true
                    opacity: (cellMa.containsMouse || cell.isCurrent) ? 1.0 : 0.72
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                Text {
                    anchors.centerIn: parent
                    visible: win.isVideo(cell.modelData)
                    text: "Video"
                    color: win.th.onSurfaceVariant
                    font.family: win.th.body; font.pixelSize: win.th.fs(11)
                }
                // Mark on the one in use.
                Rectangle {
                    visible: cell.isCurrent
                    x: 8; y: 8
                    width: nowText.implicitWidth + 14; height: 20
                    radius: win.th.rSmall
                    color: win.th.surfaceText
                    Text { id: nowText; anchors.centerIn: parent; text: "In use"
                           color: win.th.surface
                           font.family: win.th.body; font.pixelSize: win.th.fs(9); font.weight: Font.Bold }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: win.th.r
                    color: "transparent"
                    border.width: 2
                    border.color: cellMa.containsMouse ? win.th.surfaceText : "transparent"
                }
                MouseArea {
                    id: cellMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: win.peek = cell.full
                    onExited: if (win.peek === cell.full) win.peek = ""
                    onClicked: win.apply(cell.modelData)
                }
            }
        }
    }
}
