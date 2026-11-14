// Bluetooth devices. The Control Center tile only ever flipped the adapter on
// and off; actually connecting headphones still meant opening blueman.
import QtQuick
import Quickshell
import Quickshell.Bluetooth

Overlay {
    id: win

    eyebrow: "BLUETOOTH"
    title: "Devices"
    hint: "click to connect"
    tint: th ? th.secondary : "#888"
    cardWidth: 660
    cardHeight: 560

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: !!(adapter && adapter.enabled)

    onOpened: if (adapter && adapter.enabled) adapter.discovering = true
    onShownChanged: {
        // Scanning drains battery and floods the list; stop as soon as we close.
        if (!shown && adapter) adapter.discovering = false
    }

    readonly property var devices: {
        var out = []
        if (!adapter || !adapter.devices) return out
        var all = adapter.devices.values || []
        for (var i = 0; i < all.length; i++) {
            var d = all[i]
            if (!d) continue
            var n = ("" + (d.name || d.deviceName || "")).trim()
            // Unnamed devices are almost always passing strangers' phones.
            if (n.length === 0) continue
            out.push(d)
        }
        out.sort(function (a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (a.paired !== b.paired) return a.paired ? -1 : 1
            return ("" + (a.name || "")).localeCompare("" + (b.name || ""))
        })
        return out
    }

    function nameOf(d) { return ("" + (d.name || d.deviceName || "device")).trim() }
    function stateOf(d) {
        if (d.connected) return "Connected"
        if (d.paired || d.bonded) return "Paired"
        return "Available"
    }

    function toggle(d) {
        if (d.connected) { d.disconnect() }
        else if (d.paired || d.bonded) { d.connect() }
        else { d.pair() }
    }

    Item {
        anchors.fill: parent

        ListView {
            anchors.fill: parent
            anchors.margins: win.th.pad
            anchors.bottomMargin: 56
            clip: true
            spacing: 6
            model: win.devices
            visible: win.on && win.devices.length > 0
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: 60
                radius: win.th.r
                color: modelData.connected ? win.th.secondaryContainer
                                           : (devMa.containsMouse ? win.th.surfaceContainerHighest
                                                                  : win.th.surfaceContainerHigh)
                Behavior on color { ColorAnimation { duration: 140 } }

                Rectangle {
                    id: lamp
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 8; radius: 4
                    color: modelData.connected ? win.th.secondary
                                               : (modelData.paired || modelData.bonded
                                                  ? win.th.outline : win.th.outlineVariant)
                }
                Column {
                    anchors.left: lamp.right
                    anchors.leftMargin: 14
                    anchors.right: batteryText.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        text: win.nameOf(modelData)
                        color: modelData.connected ? win.th.secondaryContainerText : win.th.surfaceText
                        font.family: win.th.body; font.pixelSize: win.th.fs(13)
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: win.stateOf(modelData)
                              + (modelData.address ? "  ·  " + modelData.address : "")
                        color: modelData.connected ? win.th.secondaryContainerText : win.th.onSurfaceVariant
                        font.family: win.th.mono; font.pixelSize: win.th.fs(9)
                        elide: Text.ElideRight
                    }
                }
                Text {
                    id: batteryText
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!modelData.batteryAvailable
                    text: Math.round((modelData.battery <= 1 ? modelData.battery * 100 : modelData.battery)) + "%"
                    color: modelData.connected ? win.th.secondaryContainerText : win.th.onSurfaceVariant
                    font.family: win.th.mono; font.pixelSize: win.th.fs(11)
                }
                MouseArea {
                    id: devMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.toggle(modelData)
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: !win.on || win.devices.length === 0
            horizontalAlignment: Text.AlignHCenter
            text: !win.on ? "Bluetooth is off"
                          : (win.adapter && win.adapter.discovering
                             ? "Scanning for devices…" : "No devices yet")
            color: win.th.onSurfaceVariant
            font.family: win.th.body; font.pixelSize: win.th.fs(13)
        }

        Row {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.leftMargin: win.th.pad
            anchors.bottomMargin: 14
            spacing: 8
            Rectangle {
                width: 118; height: 30; radius: win.th.rSmall
                color: pwrMa.containsMouse
                       ? (win.on ? win.th.errorContainer : win.th.primaryContainer)
                       : win.th.surfaceContainerHigh
                Text {
                    anchors.centerIn: parent
                    text: win.on ? "Turn Bluetooth off" : "Turn Bluetooth on"
                    color: pwrMa.containsMouse
                           ? (win.on ? win.th.errorContainerText : win.th.primaryContainerText)
                           : win.th.onSurfaceVariant
                    font.family: win.th.body; font.pixelSize: win.th.fs(10)
                }
                MouseArea { id: pwrMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (win.adapter) win.adapter.enabled = !win.adapter.enabled }
            }
            Rectangle {
                width: 84; height: 30; radius: win.th.rSmall
                visible: win.on
                color: scanMa.containsMouse ? win.th.secondaryContainer : win.th.surfaceContainerHigh
                Text {
                    anchors.centerIn: parent
                    text: (win.adapter && win.adapter.discovering) ? "Scanning" : "Scan"
                    color: scanMa.containsMouse ? win.th.secondaryContainerText : win.th.onSurfaceVariant
                    font.family: win.th.body; font.pixelSize: win.th.fs(11)
                }
                MouseArea { id: scanMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (win.adapter) win.adapter.discovering = !win.adapter.discovering }
            }
        }
    }
}
