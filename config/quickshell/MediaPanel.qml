// The song menu.
//
// There is no local music library on this machine and no local player installed,
// so browsing files would be dead weight. What is actually ambiguous here is
// *which* player the shell should follow: Brave alone can expose several. This
// lists every MPRIS player and lets you pin the one the bar and music panel
// control.
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Overlay {
    id: win

    property string preferred: ""
    signal pick(string dbusName)

    eyebrow: "MEDIA"
    title: "Players"
    hint: "click to control"
    tint: th ? th.tertiary : "#888"
    cardWidth: 720
    cardHeight: 460

    readonly property var players: {
        var out = []
        var list = Mpris.players ? Mpris.players.values : []
        for (var i = 0; i < list.length; i++) {
            var p = list[i]
            if (!p) continue
            // playerctld mirrors another player's identity; controlling it is unreliable.
            if (("" + (p.dbusName || "")).toLowerCase().indexOf("playerctld") >= 0) continue
            out.push(p)
        }
        return out
    }

    function label(p) {
        if (!p) return ""
        var t = ("" + (p.trackTitle || "")).trim()
        return t.length > 0 ? t : "Nothing playing"
    }

    Item {
        anchors.fill: parent

        Text {
            anchors.centerIn: parent
            visible: win.players.length === 0
            text: "No media players running.\nStart something playing and it will show up here."
            horizontalAlignment: Text.AlignHCenter
            color: win.th.onSurfaceVariant
            font.family: win.th.body; font.pixelSize: win.th.fs(13)
            lineHeight: 1.4
        }

        ListView {
            anchors.fill: parent
            anchors.margins: win.th.pad
            clip: true
            spacing: 8
            model: win.players
            visible: win.players.length > 0
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                required property var modelData
                readonly property bool isActive:
                    win.preferred.length > 0
                    ? modelData.dbusName === win.preferred
                    : modelData.playbackState === MprisPlaybackState.Playing
                readonly property bool isPlaying:
                    modelData.playbackState === MprisPlaybackState.Playing

                width: ListView.view.width
                height: 74
                radius: win.th.r
                color: isActive ? win.th.tertiaryContainer : win.th.surfaceContainerHigh
                Behavior on color { ColorAnimation { duration: 150 } }

                Rectangle {
                    id: art
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 54; height: 54
                    radius: win.th.rSmall
                    color: win.th.surfaceContainer
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: modelData.trackArtUrl || ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !modelData.trackArtUrl
                        text: ""
                        color: win.th.onSurfaceVariant
                        font.family: win.th.icon; font.pixelSize: win.th.fs(20)
                    }
                }

                Column {
                    anchors.left: art.right
                    anchors.leftMargin: 14
                    anchors.right: controls.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        width: parent.width
                        text: win.label(modelData)
                        color: parent.parent.isActive ? win.th.tertiaryContainerText : win.th.surfaceText
                        font.family: win.th.display; font.pixelSize: win.th.fs(15); font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: ("" + (modelData.identity || "player"))
                              + (modelData.trackArtist ? "  ·  " + modelData.trackArtist : "")
                        color: parent.parent.isActive ? win.th.tertiaryContainerText : win.th.onSurfaceVariant
                        opacity: 0.9
                        font.family: win.th.mono; font.pixelSize: win.th.fs(10)
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: controls
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Rectangle {
                        width: 38; height: 32; radius: win.th.rSmall
                        color: win.th.surfaceContainer
                        Text { anchors.centerIn: parent; text: ""
                               color: win.th.onSurfaceVariant
                               font.family: win.th.icon; font.pixelSize: win.th.fs(12) }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: if (modelData.canGoPrevious) modelData.previous() }
                    }
                    Rectangle {
                        width: 44; height: 32; radius: win.th.rSmall
                        color: win.th.tertiary
                        Text { anchors.centerIn: parent
                               text: parent.parent.parent.isPlaying ? "" : ""
                               color: win.th.tertiaryText
                               font.family: win.th.icon; font.pixelSize: win.th.fs(13) }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.togglePlaying() }
                    }
                    Rectangle {
                        width: 38; height: 32; radius: win.th.rSmall
                        color: win.th.surfaceContainer
                        Text { anchors.centerIn: parent; text: ""
                               color: win.th.onSurfaceVariant
                               font.family: win.th.icon; font.pixelSize: win.th.fs(12) }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: if (modelData.canGoNext) modelData.next() }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.pick("" + modelData.dbusName)
                }
            }
        }
    }
}
