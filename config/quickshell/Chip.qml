// A choice chip. Chosen = reversed (pale block, dark text), the same rule the
// rest of the shell uses for selection. An optional colour dot sits before
// the label.
import QtQuick

Rectangle {
    id: chip

    property var    th
    property string label: ""
    property string glyph: ""
    property bool   on: false
    property bool   strong: false          // filled even when not chosen (a main action)
    property color  dot: "transparent"
    property bool   hasDot: false
    property var    onPick: null
    readonly property alias hovered: ma.containsMouse

    implicitHeight: 32
    implicitWidth: row.implicitWidth + 24
    height: implicitHeight
    radius: th.r
    color: (on || (strong && ma.containsMouse)) ? th.surfaceText
         : strong ? th.surfaceContainerHighest
         : (ma.containsMouse ? th.surfaceContainerHighest : th.surfaceContainer)
    Behavior on color { ColorAnimation { duration: 120 } }

    readonly property color fg: (on || (strong && ma.containsMouse)) ? th.surface : th.onSurfaceVariant

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Rectangle {
            visible: chip.hasDot
            anchors.verticalCenter: parent.verticalCenter
            width: 11; height: 11; radius: 5.5
            color: chip.dot
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.18)
        }
        Text {
            visible: chip.glyph.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: chip.glyph
            color: chip.fg
            font.family: chip.th.icon
            font.pixelSize: chip.th.fs(11)
        }
        Text {
            visible: chip.label.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: chip.label
            color: chip.fg
            font.family: chip.th.body
            font.pixelSize: chip.th.fs(11)
            font.weight: Font.DemiBold
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (chip.onPick) chip.onPick()
    }
}
