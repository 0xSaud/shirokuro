// Quickshell lock screen, authenticating through PAM.
//
// SAFETY: a lock screen that cannot authenticate strands you. This one keeps an
// escape hatch — `qs ipc call lock release` unlocks without a password, which is
// no weaker than `loginctl unlock-session` since both already require a logged-in
// TTY or SSH session. Test it once with a TTY reachable (Ctrl+Alt+F3) before
// making it the default locker.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Services.Pam

WlSessionLock {
    id: lock

    property var    th
    property string wallpaper: ""
    property string userName: "reouii"
    // The chosen GIF, shown as the avatar above the password field.
    property string gifPath: ""
    property real   gifZoom: 1.0
    property real   gifOffX: 0.5
    property real   gifOffY: 0.5
    readonly property bool hasGif: gifPath.length > 0
    property string trackTitle: ""
    property string trackArtist: ""
    property bool   trackPlaying: false
    property int    batPct: -1
    property bool   batCharging: false

    // Shared across surfaces so typing on either monitor fills the same field.
    property string pw: ""
    property string status: ""
    property bool   busy: false
    property bool   failed: false

    property PamContext pam: PamContext {
        // /etc/pam.d/hyprlock exists on this machine and is written for exactly
        // this job, so we reuse it rather than shipping another PAM config.
        config: "hyprlock"
        user: lock.userName

        onPamMessage: {
            if (this.responseRequired && lock.busy) {
                // The conversation is asking for the password we already have.
                this.respond(lock.pw)
            } else if (this.message && this.message.length > 0 && this.messageIsError) {
                lock.status = this.message
            }
        }
        onCompleted: function (result) {
            lock.busy = false
            if (result === PamResult.Success) {
                lock.status = ""
                lock.pw = ""
                lock.failed = false
                lock.locked = false            // this is the actual unlock
            } else if (result === PamResult.MaxTries) {
                lock.failed = true
                lock.pw = ""
                lock.status = "Too many attempts. Wait a moment."
            } else {
                lock.failed = true
                lock.pw = ""
                lock.status = "Wrong password"
            }
        }
        onError: function (err) {
            lock.busy = false
            lock.failed = true
            lock.pw = ""
            lock.status = "Authentication unavailable"
        }
    }

    function submit() {
        if (busy || pw.length === 0) return
        status = ""
        failed = false
        busy = true
        // start() opens a fresh conversation; onPamMessage answers it with `pw`.
        if (!pam.start()) {
            busy = false
            failed = true
            status = "Could not start authentication"
        }
    }

    function engage() { pw = ""; status = ""; failed = false; locked = true }
    function release() { locked = false }

    surface: Component {
        WlSessionLockSurface {
            id: surf
            color: "#000000"

            Image {
                anchors.fill: parent
                source: lock.wallpaper.length > 0 ? ("file://" + lock.wallpaper) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }
            Rectangle { anchors.fill: parent; color: "#B0000000" }

            // ---- Clock ----
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.20
                spacing: 2
                // 12-hour. Qt only treats h/hh as 12-hour when the format string
                // contains AP, so the meridiem is formatted in and then split off —
                // "AM" set in 104px next to the time would swamp it.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12
                    Text {
                        id: bigClock
                        color: "#ffffff"
                        font.family: lock.th.display
                        font.pixelSize: lock.th.fs(104)
                        font.weight: Font.Light
                        text: "--:--"
                    }
                    Text {
                        id: bigAmPm
                        anchors.bottom: bigClock.bottom
                        anchors.bottomMargin: Math.round(lock.th.fs(104) * 0.20)
                        color: lock.th.primary
                        font.family: lock.th.mono
                        font.pixelSize: lock.th.fs(22)
                        font.weight: Font.Medium
                        font.letterSpacing: 1.5
                        text: ""
                    }
                }

                Timer {
                    interval: 1000; running: true; repeat: true; triggeredOnStart: true
                    onTriggered: {
                        var d = new Date()
                        var parts = Qt.formatDateTime(d, "hh:mm AP").split(" ")
                        bigClock.text = parts[0]
                        bigAmPm.text  = parts.length > 1 ? parts[1] : ""
                        bigDate.text  = Qt.formatDateTime(d, "dddd, dd MMMM")
                    }
                }
                Text {
                    id: bigDate
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: lock.th.primary
                    font.family: lock.th.mono
                    font.pixelSize: lock.th.fs(13)
                    font.letterSpacing: 2.0
                    text: Qt.formatDateTime(new Date(), "dddd, dd MMMM")
                }
            }

            // ---- Password ----
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 40
                spacing: 14

                // Avatar. ClippingRectangle rather than `clip: true`, because
                // plain clipping is rectangular and would square off the circle.
                ClippingRectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 124; height: 124
                    radius: width / 2
                    color: "#40000000"
                    border.width: 3
                    border.color: lock.failed ? lock.th.error : lock.th.primary
                    Behavior on border.color { ColorAnimation { duration: 160 } }

                    GifView {
                        anchors.fill: parent
                        th: lock.th
                        // NOT gated on lock.locked: that property does not read
                        // back as true from inside the surface, which left this
                        // blank and frozen. The surface only exists while locked
                        // anyway, so the gate bought nothing.
                        source: lock.hasGif ? ("file://" + lock.gifPath) : ""
                        zoom: lock.gifZoom
                        offsetX: lock.gifOffX
                        offsetY: lock.gifOffY
                        playing: true
                        visible: lock.hasGif
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !lock.hasGif
                        text: lock.userName.length > 0 ? lock.userName.charAt(0).toUpperCase() : "?"
                        color: lock.th.primary
                        font.family: lock.th.display
                        font.pixelSize: lock.th.fs(46)
                        font.weight: Font.Light
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !lock.hasGif
                        text: lock.userName.length > 0 ? lock.userName.charAt(0).toUpperCase() : "?"
                        color: lock.th.primary
                        font.family: lock.th.display
                        font.pixelSize: lock.th.fs(46)
                        font.weight: Font.Light
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Hey, " + lock.userName
                    color: "#e8e8e8"
                    font.family: lock.th.display; font.pixelSize: lock.th.fs(17)
                }

                Rectangle {
                    id: field
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 340; height: 50
                    radius: lock.th.rPill
                    color: "#30000000"
                    border.width: 2
                    border.color: lock.failed ? lock.th.error
                                              : (input.activeFocus ? lock.th.primary : "#50ffffff")
                    Behavior on border.color { ColorAnimation { duration: 160 } }

                    TextInput {
                        id: input
                        anchors.fill: parent
                        anchors.leftMargin: 22
                        anchors.rightMargin: 22
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        color: "#ffffff"
                        font.family: lock.th.body
                        font.pixelSize: lock.th.fs(16)
                        enabled: !lock.busy
                        focus: true
                        text: lock.pw
                        onTextChanged: lock.pw = text
                        Component.onCompleted: forceActiveFocus()
                        onAccepted: lock.submit()

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: input.text.length === 0
                            text: lock.busy ? "Checking…" : "Password"
                            color: "#80ffffff"
                            font.family: lock.th.body; font.pixelSize: lock.th.fs(15)
                        }
                    }
                    // Keep focus on this surface's field whenever the lock is up.
                    Connections {
                        target: lock
                        function onLockedChanged() { if (lock.locked) input.forceActiveFocus() }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: lock.status
                    color: lock.th.error
                    font.family: lock.th.mono; font.pixelSize: lock.th.fs(11)
                    visible: text.length > 0
                }
            }

            // ---- Now playing ----
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 60
                visible: lock.trackTitle.length > 0
                width: Math.min(460, npCol.implicitWidth + 44)
                height: 62
                radius: lock.th.rLarge
                color: "#33000000"
                border.width: 1
                border.color: "#28ffffff"

                Rectangle {
                    id: npDot
                    x: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: 5; height: 26; radius: 2.5
                    color: lock.th.tertiary
                }
                Column {
                    id: npCol
                    anchors.left: npDot.right
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: lock.trackTitle
                        color: "#ffffff"
                        font.family: lock.th.display; font.pixelSize: lock.th.fs(14); font.weight: Font.Medium
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 380)
                    }
                    Text {
                        text: (lock.trackPlaying ? "PLAYING" : "PAUSED")
                              + (lock.trackArtist.length > 0 ? "  ·  " + lock.trackArtist : "")
                        color: lock.th.tertiary
                        font.family: lock.th.mono; font.pixelSize: lock.th.fs(10); font.letterSpacing: 1.0
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 380)
                    }
                }
            }

            // ---- Battery ----
            Text {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 26
                visible: lock.batPct >= 0
                text: (lock.batCharging ? "CHARGING  " : "") + lock.batPct + "%"
                color: "#c0ffffff"
                font.family: lock.th.mono; font.pixelSize: lock.th.fs(11); font.letterSpacing: 1.2
            }
        }
    }
}
