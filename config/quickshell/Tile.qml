// A titled tile: the building block every panel is laid out from.
// Small grey title top-left, optional note top-right, content below.
import QtQuick

Rectangle {
    id: tile

    property var    th
    property string title: ""
    property string note: ""
    default property alias content: body.data
    // Where the content area starts, for children that need to size against it.
    readonly property alias bodyWidth: body.width
    readonly property alias bodyHeight: body.height

    radius: th.rLarge
    color: th.surfaceContainerHigh

    Text {
        id: titleText
        x: 14; y: 11
        visible: tile.title.length > 0
        text: tile.title
        color: tile.th.outline
        font.family: tile.th.body
        font.pixelSize: tile.th.fs(10)
        font.weight: Font.DemiBold
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: 11
        visible: tile.note.length > 0
        text: tile.note
        color: tile.th.outline
        font.family: tile.th.body
        font.pixelSize: tile.th.fs(10)
    }
    Item {
        id: body
        x: 12
        y: tile.title.length > 0 ? 34 : 12
        width: parent.width - 24
        height: parent.height - y - 12
    }
}
